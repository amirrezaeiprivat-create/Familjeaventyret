-- Let family admins prepare next week's chores with a count or chosen weekdays.
create or replace function public.add_scheduled_weekly_chores(
  p_plan_id uuid,
  p_title text,
  p_description text,
  p_xp integer,
  p_tokens integer,
  p_assignees uuid[],
  p_difficulty text,
  p_frequency integer default null,
  p_weekdays integer[] default null
)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_plan public.weekly_plans%rowtype;
  v_next_week date := date_trunc('week', now() at time zone 'Europe/Stockholm')::date + 7;
  v_day integer;
  v_day_name text;
  v_index integer := 0;
  v_total integer;
  v_title text;
  v_chore uuid;
  v_member uuid;
begin
  if auth.uid() is null then raise exception 'Logga in för att fortsätta.'; end if;
  select * into v_plan from public.weekly_plans where id=p_plan_id for update;
  if not found or not public.app_is_family_admin(v_plan.family_id) then
    raise exception 'Veckoplanen hittades inte eller så saknas administratörsbehörighet.';
  end if;
  if v_plan.week_start <> v_next_week then raise exception 'Du kan bara planera sysslor för nästa vecka.'; end if;
  if v_plan.status <> 'open' then raise exception 'Planen för nästa vecka är stängd.'; end if;
  if length(trim(coalesce(p_title,''))) < 1 or length(trim(p_title)) > 85 then raise exception 'Ange ett sysslenamn med 1 till 85 tecken.'; end if;
  if coalesce(array_length(p_assignees,1),0)=0 then raise exception 'Välj minst en familjemedlem.'; end if;
  if p_difficulty not in ('Lätt','Mellan','Svår') then raise exception 'Ogiltig svårighetsgrad.'; end if;
  if p_xp is null or p_xp < 0 or p_xp > 500 or p_tokens is null or p_tokens < 0 or p_tokens > 100 then raise exception 'Ogiltig XP- eller myntbelöning.'; end if;

  foreach v_member in array p_assignees loop
    if not exists(select 1 from public.family_members where family_id=v_plan.family_id and user_id=v_member and is_active) then
      raise exception 'Alla valda personer måste vara aktiva familjemedlemmar.';
    end if;
  end loop;

  if p_weekdays is not null and cardinality(p_weekdays)>0 then
    if p_frequency is not null then raise exception 'Välj antingen antal tillfällen eller veckodagar.'; end if;
    if exists(select 1 from unnest(p_weekdays) as selected(day) where selected.day not between 1 and 7)
       or cardinality(p_weekdays) <> (select count(distinct selected.day)::integer from unnest(p_weekdays) as selected(day)) then
      raise exception 'Välj giltiga veckodagar, en gång vardera.';
    end if;
    v_total := cardinality(p_weekdays);
    for v_day in select distinct selected.day from unnest(p_weekdays) as selected(day) order by selected.day loop
      v_index := v_index + 1;
      v_day_name := case v_day when 1 then 'måndag' when 2 then 'tisdag' when 3 then 'onsdag' when 4 then 'torsdag' when 5 then 'fredag' when 6 then 'lördag' else 'söndag' end;
      v_title := trim(p_title)||' · '||v_day_name;
      insert into public.chores(family_id,plan_id,title,description,difficulty,xp_reward,token_reward,created_by)
      values(v_plan.family_id,v_plan.id,v_title,coalesce(trim(p_description),''),p_difficulty,p_xp,p_tokens,auth.uid()) returning id into v_chore;
      insert into public.chore_assignments(family_id,chore_id,user_id,assigned_by)
      select v_plan.family_id,v_chore,selected.user_id,auth.uid() from (select distinct unnest(p_assignees) as user_id) selected;
    end loop;
  else
    if p_frequency is null or p_frequency not between 1 and 7 then raise exception 'Välj mellan 1 och 7 tillfällen per vecka.'; end if;
    v_total := p_frequency;
    for v_index in 1..v_total loop
      v_title := case when v_total=1 then trim(p_title) else trim(p_title)||' · tillfälle '||v_index||'/'||v_total end;
      insert into public.chores(family_id,plan_id,title,description,difficulty,xp_reward,token_reward,created_by)
      values(v_plan.family_id,v_plan.id,v_title,coalesce(trim(p_description),''),p_difficulty,p_xp,p_tokens,auth.uid()) returning id into v_chore;
      insert into public.chore_assignments(family_id,chore_id,user_id,assigned_by)
      select v_plan.family_id,v_chore,selected.user_id,auth.uid() from (select distinct unnest(p_assignees) as user_id) selected;
    end loop;
  end if;
  return v_total;
end;
$$;

-- Keep future-plan chores unavailable until their scheduled week is current.
create or replace function public.submit_chore(p_chore_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_chore public.chores%rowtype; v_submission uuid; v_deadline timestamptz; v_grace public.creature_effects%rowtype;
begin
  select * into v_chore from public.chores where id=p_chore_id and is_active for update;
  if not found or not public.app_is_family_member(v_chore.family_id) then raise exception 'Chore not found or family access required'; end if;
  if not exists(select 1 from public.chore_assignments where chore_id=v_chore.id and user_id=auth.uid()) then raise exception 'This chore is not assigned to you'; end if;
  if v_chore.kind='weekly' then
    if exists(select 1 from public.chores where family_id=v_chore.family_id and kind='curse' and resolved_at is null) then raise exception 'Resolve active curses first'; end if;
    if not exists(select 1 from public.weekly_plans where id=v_chore.plan_id and status='open' and week_start=date_trunc('week',now() at time zone 'Europe/Stockholm')::date) then raise exception 'This weekly plan is not active yet or is closed'; end if;
    select coalesce(a.deadline_at,v_chore.deadline_at) into v_deadline from public.chore_assignments a where a.chore_id=v_chore.id and a.user_id=auth.uid();
    if v_deadline is not null and now()>v_deadline then
      select * into v_grace from public.creature_effects where family_id=v_chore.family_id and user_id=auth.uid() and effect_key='deadline_grace' and payload->>'chore_id'=v_chore.id::text and uses_remaining>0 and (expires_at is null or expires_at>now()) order by created_at limit 1 for update;
      if not found then raise exception 'This task deadline has passed'; end if;
      update public.creature_effects set uses_remaining=uses_remaining-1 where id=v_grace.id;
    end if;
  end if;
  if exists(select 1 from public.quest_submissions where chore_id=v_chore.id and user_id=auth.uid() and status in ('pending_approval','approved')) then raise exception 'This chore is already submitted'; end if;
  insert into public.quest_submissions(family_id,chore_id,user_id,xp_reward,token_reward)
  values(v_chore.family_id,v_chore.id,auth.uid(),case when v_chore.kind='curse' then 0 else v_chore.xp_reward end,case when v_chore.kind='curse' then 0 else v_chore.token_reward end)
  returning id into v_submission;
  return v_submission;
end $$;

revoke all on function public.add_scheduled_weekly_chores(uuid,text,text,integer,integer,uuid[],text,integer,integer[]) from public, anon;
grant execute on function public.add_scheduled_weekly_chores(uuid,text,text,integer,integer,uuid[],text,integer,integer[]) to authenticated;
notify pgrst, 'reload schema';
