-- Connect the weekly reward ledger to a free, openable diamond chest credit.
-- The credit source is tied to one reward row, so retries cannot duplicate it.
create unique index if not exists creature_chest_credits_weekly_reward_uidx
  on public.creature_chest_credits(user_id, source)
  where source like 'weekly_reward:%';

-- Backfill previously awarded weekly chests that have not been opened.
insert into public.creature_chest_credits(family_id,user_id,chest_type,source)
select wr.family_id,wr.user_id,'diamond','weekly_reward:'||wr.id::text
from public.weekly_rewards wr
where wr.opened_at is null
on conflict do nothing;

create or replace function public.close_weekly_plan(p_plan_id uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_plan public.weekly_plans%rowtype;
  v_count integer;
begin
  select * into v_plan from public.weekly_plans where id=p_plan_id for update;
  if not found or not public.app_is_family_admin(v_plan.family_id) then
    raise exception 'Weekly plan not found or admin access required';
  end if;
  if v_plan.status='closed' then return 0; end if;
  if exists(select 1 from public.chores where family_id=v_plan.family_id and kind='curse' and resolved_at is null) then
    raise exception 'Resolve all curses before closing the week';
  end if;
  if not exists(select 1 from public.chores where plan_id=v_plan.id and kind='weekly' and is_active) then
    raise exception 'Add weekly chores before closing the week';
  end if;
  if exists(
    select 1 from public.chores c
    where c.plan_id=v_plan.id and c.kind='weekly' and c.is_active
      and not exists(select 1 from public.chore_assignments a where a.chore_id=c.id)
  ) then raise exception 'Assign every weekly chore before closing the week'; end if;
  if exists(
    select 1
    from public.chore_assignments a
    join public.chores c on c.id=a.chore_id and c.kind='weekly' and c.is_active
    left join public.quest_submissions s on s.chore_id=a.chore_id and s.user_id=a.user_id and s.status='approved'
    where c.plan_id=v_plan.id and s.id is null
  ) then raise exception 'Every assigned chore must be approved before the family reward is granted'; end if;

  update public.weekly_plans set status='closed',closed_at=now() where id=v_plan.id;
  insert into public.weekly_rewards(family_id,plan_id,user_id)
    select v_plan.family_id,v_plan.id,user_id
    from public.family_members where family_id=v_plan.family_id and is_active
    on conflict(plan_id,user_id,chest_type) do nothing;
  get diagnostics v_count = row_count;

  insert into public.creature_chest_credits(family_id,user_id,chest_type,source)
    select wr.family_id,wr.user_id,'diamond','weekly_reward:'||wr.id::text
    from public.weekly_rewards wr
    where wr.plan_id=v_plan.id and wr.opened_at is null
    on conflict do nothing;

  return v_count;
end;
$$;

revoke all on function public.close_weekly_plan(uuid) from public,anon;
grant execute on function public.close_weekly_plan(uuid) to authenticated;
notify pgrst, 'reload schema';
