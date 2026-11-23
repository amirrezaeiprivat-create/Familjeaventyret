-- Allow family admins to edit an unsubmitted chore in the current open week.
create or replace function public.admin_update_current_weekly_chore(
  p_chore_id uuid,
  p_title text,
  p_description text,
  p_xp integer,
  p_tokens integer,
  p_difficulty text,
  p_assignees uuid[],
  p_scheduled_for date default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_chore public.chores%rowtype;
  v_plan public.weekly_plans%rowtype;
  v_title text;
  v_suffix text := '';
  v_member uuid;
  v_current_week date := date_trunc('week', now() at time zone 'Europe/Stockholm')::date;
begin
  if auth.uid() is null then raise exception 'Logga in för att fortsätta.'; end if;

  select * into v_chore
  from public.chores
  where id = p_chore_id and kind = 'weekly' and is_active
  for update;
  if not found or not public.app_is_family_admin(v_chore.family_id) then
    raise exception 'Sysslan hittades inte eller så saknas administratörsbehörighet.';
  end if;

  select * into v_plan
  from public.weekly_plans
  where id = v_chore.plan_id and family_id = v_chore.family_id
  for update;
  if not found or v_plan.status <> 'open' or v_plan.week_start <> v_current_week then
    raise exception 'Endast sysslor i den öppna innevarande veckan kan redigeras.';
  end if;
  if exists(select 1 from public.quest_submissions where chore_id = v_chore.id) then
    raise exception 'En inskickad syssla kan inte redigeras.';
  end if;
  if length(trim(coalesce(p_title, ''))) not between 1 and 85 then
    raise exception 'Ange ett sysslenamn med 1 till 85 tecken.';
  end if;
  if length(coalesce(p_description, '')) > 300 then
    raise exception 'Beskrivningen får vara högst 300 tecken.';
  end if;
  if p_difficulty not in ('Lätt', 'Mellan', 'Svår') then raise exception 'Ogiltig svårighetsgrad.'; end if;
  if p_xp is null or p_xp not between 0 and 500 or p_tokens is null or p_tokens not between 0 and 100 then
    raise exception 'Ogiltig XP- eller myntbelöning.';
  end if;
  if coalesce(cardinality(p_assignees), 0) < 1 then raise exception 'Välj minst en ansvarig person.'; end if;
  if cardinality(p_assignees) <> (select count(distinct selected.user_id)::integer from unnest(p_assignees) as selected(user_id)) then
    raise exception 'Samma familjemedlem kan inte väljas flera gånger.';
  end if;
  if p_scheduled_for is not null then
    if p_scheduled_for < v_plan.week_start or p_scheduled_for > v_plan.week_start + 6 then
      raise exception 'Den planerade dagen måste ligga i innevarande vecka.';
    end if;
    if cardinality(p_assignees) <> 1 then raise exception 'En uppgift med bestämd dag måste ha exakt en ansvarig.'; end if;
    v_suffix := case extract(isodow from p_scheduled_for)::integer
      when 1 then ' · måndag' when 2 then ' · tisdag' when 3 then ' · onsdag'
      when 4 then ' · torsdag' when 5 then ' · fredag' when 6 then ' · lördag' else ' · söndag'
    end;
  end if;
  v_title := trim(p_title) || v_suffix;
  if exists(select 1 from public.chores where id <> v_chore.id and plan_id = v_plan.id and title = v_title and is_active) then
    raise exception 'En syssla med samma namn finns redan i veckoplanen.';
  end if;
  foreach v_member in array p_assignees loop
    if not exists(select 1 from public.family_members where family_id = v_chore.family_id and user_id = v_member and is_active) then
      raise exception 'Alla ansvariga måste vara aktiva familjemedlemmar.';
    end if;
  end loop;

  update public.chores
  set title = v_title, description = coalesce(trim(p_description), ''),
      xp_reward = p_xp, token_reward = p_tokens, difficulty = p_difficulty
  where id = v_chore.id;
  delete from public.chore_assignments where chore_id = v_chore.id;
  insert into public.chore_assignments(family_id, chore_id, user_id, assigned_by, scheduled_for)
  select v_chore.family_id, v_chore.id, selected.user_id, auth.uid(), p_scheduled_for
  from (select distinct unnest(p_assignees) as user_id) selected;
end;
$$;

revoke all on function public.admin_update_current_weekly_chore(uuid, text, text, integer, integer, text, uuid[], date) from public, anon;
grant execute on function public.admin_update_current_weekly_chore(uuid, text, text, integer, integer, text, uuid[], date) to authenticated;
notify pgrst, 'reload schema';
