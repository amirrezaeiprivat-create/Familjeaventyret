-- Apply after schema.sql in the Supabase SQL Editor.
alter table public.family_members add column if not exists last_streak_date date;

create or replace function public.create_family_invite(p_family_id uuid, p_role text)
returns text language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_code text := replace(gen_random_uuid()::text,'-','');
begin
  if not public.app_is_family_admin(p_family_id) then raise exception 'Only family admins can create invites'; end if;
  if p_role not in ('admin','player') then raise exception 'Invalid family role'; end if;
  if p_role='admin' and (select count(*) from public.family_members where family_id=p_family_id and role='admin' and is_active) >= 2 then raise exception 'This family already has two active administrators'; end if;
  insert into public.family_invites(family_id,invite_code,role,created_by) values (p_family_id,v_code,p_role,auth.uid());
  return v_code;
end $$;

create or replace function public.join_family(p_invite_code text, p_display_name text)
returns uuid language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_user uuid := auth.uid(); v_invite public.family_invites%rowtype;
begin
  if v_user is null then raise exception 'Sign in first'; end if;
  if length(trim(coalesce(p_display_name,''))) < 1 then raise exception 'Enter a display name'; end if;
  select * into v_invite from public.family_invites where invite_code=trim(p_invite_code) and claimed_at is null and expires_at>now() for update;
  if not found then raise exception 'Invite code is invalid, expired, or already used'; end if;
  if exists(select 1 from public.family_members where user_id=v_user) then raise exception 'This account already belongs to a family'; end if;
  if v_invite.role='admin' then
    perform 1 from public.families where id=v_invite.family_id for update;
    if (select count(*) from public.family_members where family_id=v_invite.family_id and role='admin' and is_active) >= 2 then raise exception 'This family already has two active administrators'; end if;
  end if;
  insert into public.family_members(family_id,user_id,display_name,role) values(v_invite.family_id,v_user,trim(p_display_name),v_invite.role);
  update public.family_invites set claimed_by=v_user,claimed_at=now() where id=v_invite.id;
  return v_invite.family_id;
end $$;

create or replace function public.decide_quest_submission(p_submission_id uuid,p_decision text,p_reason text default '')
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_sub public.quest_submissions%rowtype; v_chore public.chores%rowtype; v_admin_name text; v_today date := (now() at time zone 'Europe/Stockholm')::date;
begin
  if p_decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
  select * into v_sub from public.quest_submissions where id=p_submission_id for update;
  if not found or v_sub.status <> 'pending_approval' then raise exception 'Submission is no longer pending'; end if;
  if not public.app_is_family_admin(v_sub.family_id) then raise exception 'Only a family admin can decide submissions'; end if;
  if v_sub.user_id=auth.uid() then raise exception 'You cannot decide your own submission'; end if;
  select * into v_chore from public.chores where id=v_sub.chore_id for update;
  select display_name into v_admin_name from public.family_members where family_id=v_sub.family_id and user_id=auth.uid();
  update public.quest_submissions set status=p_decision,decided_by=auth.uid(),decided_at=now(),rejection_reason=case when p_decision='rejected' then left(trim(coalesce(p_reason,'')),500) else '' end,rewarded_at=case when p_decision='approved' and v_chore.kind='weekly' then now() else null end where id=v_sub.id;
  if v_chore.kind='curse' then
    if p_decision='approved' then update public.chores set resolved_at=now() where id=v_chore.id; end if;
  elsif p_decision='approved' then
    update public.family_members
    set xp=xp+v_sub.xp_reward,
        tokens=tokens+v_sub.token_reward,
        streak=case when last_streak_date=v_today then streak when last_streak_date=v_today-1 then streak+1 else 1 end,
        last_streak_date=v_today
    where family_id=v_sub.family_id and user_id=v_sub.user_id;
  end if;
  insert into public.notifications(family_id,user_id,message) values(v_sub.family_id,v_sub.user_id,case when p_decision='approved' then v_chore.title||' godkändes av '||coalesce(v_admin_name,'en administratör')||'.' else v_chore.title||' nekades.'||case when trim(coalesce(p_reason,''))<>'' then ' Anledning: '||left(trim(p_reason),500) else '' end end);
end $$;

create or replace function public.close_weekly_plan(p_plan_id uuid)
returns integer language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_plan public.weekly_plans%rowtype; v_count integer;
begin
  select * into v_plan from public.weekly_plans where id=p_plan_id for update;
  if not found or not public.app_is_family_admin(v_plan.family_id) then raise exception 'Weekly plan not found or admin access required'; end if;
  if v_plan.status='closed' then return 0; end if;
  if exists(select 1 from public.chores where family_id=v_plan.family_id and kind='curse' and resolved_at is null) then raise exception 'Resolve all curses before closing the week'; end if;
  if not exists(select 1 from public.chores where plan_id=v_plan.id and kind='weekly' and is_active) then raise exception 'Add weekly chores before closing the week'; end if;
  if exists(select 1 from public.chores c where c.plan_id=v_plan.id and c.kind='weekly' and c.is_active and not exists(select 1 from public.chore_assignments a where a.chore_id=c.id)) then raise exception 'Assign every weekly chore before closing the week'; end if;
  if exists(select 1 from public.chore_assignments a join public.chores c on c.id=a.chore_id and c.kind='weekly' and c.is_active left join public.quest_submissions s on s.chore_id=a.chore_id and s.user_id=a.user_id and s.status='approved' where c.plan_id=v_plan.id and s.id is null) then raise exception 'Every assigned chore must be approved before the family reward is granted'; end if;
  update public.weekly_plans set status='closed',closed_at=now() where id=v_plan.id;
  insert into public.weekly_rewards(family_id,plan_id,user_id)
  select v_plan.family_id,v_plan.id,user_id from public.family_members where family_id=v_plan.family_id and is_active
  on conflict(plan_id,user_id,chest_type) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end $$;

revoke all on function public.create_family_invite(uuid,text),public.join_family(text,text),public.decide_quest_submission(uuid,text,text),public.close_weekly_plan(uuid) from public,anon;
grant execute on function public.create_family_invite(uuid,text),public.join_family(text,text),public.decide_quest_submission(uuid,text,text),public.close_weekly_plan(uuid) to authenticated;
