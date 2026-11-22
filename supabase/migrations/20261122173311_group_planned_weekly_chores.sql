-- Manage a planned recurring chore as one editor while retaining one chore row per occurrence.
create or replace function public.admin_update_planned_weekly_chore_group(
  p_occurrence_ids uuid[],
  p_title text,
  p_description text,
  p_xp integer,
  p_tokens integer,
  p_difficulty text,
  p_mode text,
  p_frequency integer,
  p_assignees uuid[],
  p_schedule jsonb
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_anchor public.chores%rowtype;
  v_plan public.weekly_plans%rowtype;
  v_ids uuid[];
  v_target_count integer;
  v_index integer;
  v_occurrence_id uuid;
  v_day integer;
  v_day_name text;
  v_date date;
  v_member uuid;
  v_item jsonb;
  v_occurrence_title text;
  v_base_title text := trim(coalesce(p_title, ''));
begin
  if auth.uid() is null then raise exception 'Logga in för att fortsätta.'; end if;
  if coalesce(cardinality(p_occurrence_ids), 0) < 1
     or cardinality(p_occurrence_ids) <> (select count(distinct x.id)::integer from unnest(p_occurrence_ids) x(id)) then
    raise exception 'Den planerade sysslan kunde inte identifieras.';
  end if;
  select c.* into v_anchor
    from public.chores c
    where c.id = p_occurrence_ids[1] and c.kind = 'weekly' and c.is_active
    for update;
  if not found or not public.app_is_family_admin(v_anchor.family_id) then
    raise exception 'Sysslan hittades inte eller så saknas administratörsbehörighet.';
  end if;
  select * into v_plan from public.weekly_plans where id = v_anchor.plan_id for update;
  if not found or v_plan.family_id <> v_anchor.family_id or v_plan.status <> 'open'
     or v_plan.week_start <> date_trunc('week', now() at time zone 'Europe/Stockholm')::date + 7 then
    raise exception 'Endast sysslor i en öppen plan för nästa vecka kan redigeras.';
  end if;

  select array_agg(c.id order by c.id) into v_ids
  from public.chores c
  where c.plan_id = v_anchor.plan_id and c.family_id = v_anchor.family_id
    and c.kind = 'weekly' and c.is_active
    and c.created_at = v_anchor.created_at
    and c.created_by is not distinct from v_anchor.created_by
    and regexp_replace(c.title, ' · (måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag|tillfälle [0-9]+/[0-9]+|tillfälle [0-9]+)$', '', 'i')
      = regexp_replace(v_anchor.title, ' · (måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag|tillfälle [0-9]+/[0-9]+|tillfälle [0-9]+)$', '', 'i');
  if v_ids is distinct from (select array_agg(x.id order by x.id) from (select distinct unnest(p_occurrence_ids) id) x) then
    raise exception 'Alla tillfällen för sysslan måste redigeras samtidigt.';
  end if;
  if exists(select 1 from public.quest_submissions where chore_id = any(v_ids)) then
    raise exception 'En syssla med inskickade tillfällen kan inte redigeras.';
  end if;
  if length(v_base_title) not between 1 and 85 then raise exception 'Ange ett sysslenamn med 1 till 85 tecken.'; end if;
  if length(coalesce(p_description, '')) > 300 then raise exception 'Beskrivningen får vara högst 300 tecken.'; end if;
  if p_difficulty not in ('Lätt', 'Mellan', 'Svår') then raise exception 'Ogiltig svårighetsgrad.'; end if;
  if p_xp is null or p_xp not between 0 and 500 or p_tokens is null or p_tokens not between 0 and 100 then
    raise exception 'Ogiltig XP- eller myntbelöning.';
  end if;

  if p_mode = 'count' then
    if p_frequency is null or p_frequency not between 1 and 7 then raise exception 'Välj mellan 1 och 7 tillfällen i veckan.'; end if;
    if coalesce(cardinality(p_assignees), 0) < 1 then raise exception 'Välj minst en ansvarig person.'; end if;
    if cardinality(p_assignees) <> (select count(distinct x.id)::integer from unnest(p_assignees) x(id)) then raise exception 'Välj varje person högst en gång.'; end if;
    foreach v_member in array p_assignees loop
      if not exists(select 1 from public.family_members where family_id = v_anchor.family_id and user_id = v_member and is_active) then
        raise exception 'Alla ansvariga måste vara aktiva familjemedlemmar.';
      end if;
    end loop;
    v_target_count := p_frequency;
  elsif p_mode = 'days' then
    if jsonb_typeof(p_schedule) is distinct from 'array' or jsonb_array_length(p_schedule) not between 1 and 7 then
      raise exception 'Välj minst en veckodag och ansvarig person.';
    end if;
    if exists(select 1 from jsonb_array_elements(p_schedule) item(value) group by item.value->>'day' having count(*) > 1) then
      raise exception 'Varje veckodag kan bara väljas en gång.';
    end if;
    for v_item in select value from jsonb_array_elements(p_schedule) loop
      begin v_day := (v_item->>'day')::integer; v_member := (v_item->>'user_id')::uuid;
      exception when others then raise exception 'Ogiltig veckodag eller ansvarig person.'; end;
      if v_day not between 1 and 7 then raise exception 'Välj en giltig veckodag.'; end if;
      if not exists(select 1 from public.family_members where family_id = v_anchor.family_id and user_id = v_member and is_active) then
        raise exception 'Alla ansvariga måste vara aktiva familjemedlemmar.';
      end if;
    end loop;
    v_target_count := jsonb_array_length(p_schedule);
  else
    raise exception 'Välj hur sysslan ska fördelas.';
  end if;

  for v_index in 1..v_target_count loop
    if p_mode = 'count' then
      v_occurrence_title := case when v_target_count = 1 then v_base_title else v_base_title || ' · tillfälle ' || v_index || '/' || v_target_count end;
      v_date := null;
    else
      select (item.value->>'day')::integer, (item.value->>'user_id')::uuid into v_day, v_member
      from jsonb_array_elements(p_schedule) item(value)
      order by (item.value->>'day')::integer offset v_index - 1 limit 1;
      v_day_name := case v_day when 1 then 'måndag' when 2 then 'tisdag' when 3 then 'onsdag' when 4 then 'torsdag' when 5 then 'fredag' when 6 then 'lördag' else 'söndag' end;
      v_occurrence_title := v_base_title || ' · ' || v_day_name;
      v_date := v_plan.week_start + v_day - 1;
    end if;
    if exists(select 1 from public.chores c where c.plan_id = v_plan.id and c.is_active and not (c.id = any(v_ids)) and c.title = v_occurrence_title) then
      raise exception 'En annan syssla i planen har redan namnet %.', v_occurrence_title;
    end if;
  end loop;

  for v_index in 1..v_target_count loop
    if p_mode = 'count' then
      v_occurrence_title := case when v_target_count = 1 then v_base_title else v_base_title || ' · tillfälle ' || v_index || '/' || v_target_count end;
      v_date := null;
    else
      select (item.value->>'day')::integer, (item.value->>'user_id')::uuid into v_day, v_member
      from jsonb_array_elements(p_schedule) item(value)
      order by (item.value->>'day')::integer offset v_index - 1 limit 1;
      v_day_name := case v_day when 1 then 'måndag' when 2 then 'tisdag' when 3 then 'onsdag' when 4 then 'torsdag' when 5 then 'fredag' when 6 then 'lördag' else 'söndag' end;
      v_occurrence_title := v_base_title || ' · ' || v_day_name;
      v_date := v_plan.week_start + v_day - 1;
    end if;
    if v_index <= cardinality(v_ids) then
      v_occurrence_id := v_ids[v_index];
      update public.chores set title = v_occurrence_title, description = coalesce(trim(p_description), ''),
        xp_reward = p_xp, token_reward = p_tokens, difficulty = p_difficulty
        where id = v_occurrence_id;
    else
      insert into public.chores(family_id, plan_id, kind, title, description, xp_reward, token_reward, difficulty, created_by, created_at, is_active)
      values(v_anchor.family_id, v_anchor.plan_id, 'weekly', v_occurrence_title, coalesce(trim(p_description), ''), p_xp, p_tokens, p_difficulty, v_anchor.created_by, v_anchor.created_at, true)
      returning id into v_occurrence_id;
    end if;
    delete from public.chore_assignments where chore_id = v_occurrence_id;
    if p_mode = 'count' then
      insert into public.chore_assignments(family_id, chore_id, user_id, assigned_by, scheduled_for)
      select v_anchor.family_id, v_occurrence_id, x.id, auth.uid(), null from unnest(p_assignees) x(id);
    else
      insert into public.chore_assignments(family_id, chore_id, user_id, assigned_by, scheduled_for)
      values(v_anchor.family_id, v_occurrence_id, v_member, auth.uid(), v_date);
    end if;
  end loop;
  if cardinality(v_ids) > v_target_count then
    update public.chores set is_active = false where id = any(v_ids[v_target_count + 1:]);
    delete from public.chore_assignments where chore_id = any(v_ids[v_target_count + 1:]);
  end if;
  return v_target_count;
end;
$$;

create or replace function public.admin_delete_planned_weekly_chore_group(p_occurrence_ids uuid[])
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_anchor public.chores%rowtype;
  v_ids uuid[];
  v_count integer;
begin
  if auth.uid() is null then raise exception 'Logga in för att fortsätta.'; end if;
  if coalesce(cardinality(p_occurrence_ids), 0) < 1 then raise exception 'Sysslan kunde inte hittas.'; end if;
  select c.* into v_anchor from public.chores c where c.id = p_occurrence_ids[1] and c.kind = 'weekly' and c.is_active for update;
  if not found or not public.app_is_family_admin(v_anchor.family_id) then raise exception 'Sysslan hittades inte eller så saknas administratörsbehörighet.'; end if;
  if not exists(select 1 from public.weekly_plans where id = v_anchor.plan_id and family_id = v_anchor.family_id and status = 'open' and week_start = date_trunc('week', now() at time zone 'Europe/Stockholm')::date + 7) then
    raise exception 'Endast planerade sysslor i en öppen plan för nästa vecka kan tas bort.';
  end if;
  select array_agg(c.id order by c.id) into v_ids from public.chores c
  where c.plan_id = v_anchor.plan_id and c.family_id = v_anchor.family_id and c.kind = 'weekly' and c.is_active
    and c.created_at = v_anchor.created_at and c.created_by is not distinct from v_anchor.created_by
    and regexp_replace(c.title, ' · (måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag|tillfälle [0-9]+/[0-9]+|tillfälle [0-9]+)$', '', 'i')
      = regexp_replace(v_anchor.title, ' · (måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag|tillfälle [0-9]+/[0-9]+|tillfälle [0-9]+)$', '', 'i');
  if v_ids is distinct from (select array_agg(x.id order by x.id) from (select distinct unnest(p_occurrence_ids) id) x) then raise exception 'Alla tillfällen måste väljas tillsammans.'; end if;
  if exists(select 1 from public.quest_submissions where chore_id = any(v_ids) and status = 'approved') then raise exception 'En syssla med godkända tillfällen kan inte tas bort.'; end if;
  update public.quest_submissions set status = 'rejected', decided_by = auth.uid(), decided_at = now(),
    rejection_reason = 'Uppgiften togs bort av en administratör.', rewarded_at = null
    where chore_id = any(v_ids) and status = 'pending_approval';
  update public.chores set is_active = false where id = any(v_ids);
  insert into public.notifications(family_id, user_id, message)
  select distinct v_anchor.family_id, a.user_id, 'Sysslan ' || regexp_replace(v_anchor.title, ' · (måndag|tisdag|onsdag|torsdag|fredag|lördag|söndag|tillfälle [0-9]+/[0-9]+|tillfälle [0-9]+)$', '', 'i') || ' togs bort av en administratör.'
  from public.chore_assignments a where a.chore_id = any(v_ids);
  get diagnostics v_count = row_count;
  return cardinality(v_ids);
end;
$$;

revoke all on function public.admin_update_planned_weekly_chore_group(uuid[], text, text, integer, integer, text, text, integer, uuid[], jsonb) from public, anon;
grant execute on function public.admin_update_planned_weekly_chore_group(uuid[], text, text, integer, integer, text, text, integer, uuid[], jsonb) to authenticated;
revoke all on function public.admin_delete_planned_weekly_chore_group(uuid[]) from public, anon;
grant execute on function public.admin_delete_planned_weekly_chore_group(uuid[]) to authenticated;
notify pgrst, 'reload schema';

