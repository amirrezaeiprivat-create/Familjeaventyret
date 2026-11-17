-- Adds a server-validated difficulty to weekly chores.
alter table public.chores
  add column if not exists difficulty text not null default 'Lätt'
  check (difficulty in ('Lätt','Mellan','Svår'));

drop function if exists public.add_weekly_chore(uuid,text,text,integer,integer,uuid[]);

create or replace function public.add_weekly_chore(
  p_plan_id uuid,
  p_title text,
  p_description text,
  p_xp integer,
  p_tokens integer,
  p_assignees uuid[],
  p_difficulty text
)
returns uuid language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_plan public.weekly_plans%rowtype; v_chore uuid; v_member uuid;
begin
  select * into v_plan from public.weekly_plans where id=p_plan_id for update;
  if not found or not public.app_is_family_admin(v_plan.family_id) then raise exception 'Weekly plan not found or admin access required'; end if;
  if v_plan.status <> 'open' then raise exception 'This weekly plan is closed'; end if;
  if length(trim(coalesce(p_title,''))) < 1 or coalesce(array_length(p_assignees,1),0)=0 then raise exception 'Title and at least one assignee are required'; end if;
  if p_difficulty not in ('Lätt','Mellan','Svår') then raise exception 'Invalid chore difficulty'; end if;
  if p_xp < 0 or p_xp > 500 or p_tokens < 0 or p_tokens > 100 then raise exception 'Invalid rewards'; end if;
  foreach v_member in array p_assignees loop
    if not exists(select 1 from public.family_members where family_id=v_plan.family_id and user_id=v_member and is_active) then raise exception 'Every assignee must be an active member of this family'; end if;
  end loop;
  insert into public.chores(family_id,plan_id,title,description,difficulty,xp_reward,token_reward,created_by)
  values(v_plan.family_id,v_plan.id,trim(p_title),coalesce(trim(p_description),''),p_difficulty,p_xp,p_tokens,auth.uid()) returning id into v_chore;
  insert into public.chore_assignments(family_id,chore_id,user_id,assigned_by)
  select v_plan.family_id,v_chore,distinct_user,auth.uid() from (select distinct unnest(p_assignees) as distinct_user) a;
  return v_chore;
end $$;

revoke all on function public.add_weekly_chore(uuid,text,text,integer,integer,uuid[],text) from public,anon;
grant execute on function public.add_weekly_chore(uuid,text,text,integer,integer,uuid[],text) to authenticated;

notify pgrst, 'reload schema';
