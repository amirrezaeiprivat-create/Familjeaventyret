-- Family Quest data model for the Familjeäventyret Supabase project.
-- Run only after reviewing this file in Supabase SQL Editor.

create table if not exists public.families (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) between 2 and 80),
  timezone text not null default 'Europe/Stockholm',
  created_by uuid not null references auth.users(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.family_members (
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (length(trim(display_name)) between 1 and 60),
  role text not null check (role in ('admin','player')),
  is_active boolean not null default true,
  xp integer not null default 0 check (xp >= 0),
  tokens integer not null default 0 check (tokens >= 0),
  shards integer not null default 0 check (shards >= 0),
  streak integer not null default 0 check (streak >= 0),
  created_at timestamptz not null default now(),
  primary key (family_id, user_id)
);

create table if not exists public.family_invites (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  invite_code text not null unique,
  role text not null check (role in ('admin','player')),
  created_by uuid not null references auth.users(id),
  expires_at timestamptz not null default now() + interval '14 days',
  claimed_by uuid references auth.users(id),
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.weekly_plans (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  week_start date not null,
  status text not null default 'open' check (status in ('open','closed')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  unique (family_id, week_start)
);

create table if not exists public.chores (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  plan_id uuid references public.weekly_plans(id) on delete cascade,
  kind text not null default 'weekly' check (kind in ('weekly','curse')),
  title text not null check (length(trim(title)) between 1 and 100),
  description text not null default '',
  xp_reward integer not null default 0 check (xp_reward between 0 and 500),
  token_reward integer not null default 0 check (token_reward between 0 and 100),
  deadline_at timestamptz,
  resolved_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  is_active boolean not null default true,
  check (kind <> 'curse' or (xp_reward = 0 and token_reward = 0))
);

create table if not exists public.chore_assignments (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  chore_id uuid not null references public.chores(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  assigned_by uuid not null references auth.users(id),
  assigned_at timestamptz not null default now(),
  unique (chore_id, user_id)
);

create table if not exists public.quest_submissions (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  chore_id uuid not null references public.chores(id) on delete cascade,
  user_id uuid not null references auth.users(id),
  submitted_at timestamptz not null default now(),
  status text not null default 'pending_approval' check (status in ('pending_approval','approved','rejected')),
  xp_reward integer not null default 0 check (xp_reward >= 0),
  token_reward integer not null default 0 check (token_reward >= 0),
  decided_by uuid references auth.users(id),
  decided_at timestamptz,
  rejection_reason text not null default '',
  rewarded_at timestamptz
);

create unique index if not exists quest_submissions_one_pending_per_chore
  on public.quest_submissions (chore_id, user_id)
  where status = 'pending_approval';

create table if not exists public.weekly_rewards (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  plan_id uuid not null references public.weekly_plans(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  chest_type text not null default 'diamond' check (chest_type = 'diamond'),
  created_at timestamptz not null default now(),
  opened_at timestamptz,
  unique (plan_id, user_id, chest_type)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create or replace function public.app_is_family_member(p_family_id uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp
as $$ select exists (select 1 from public.family_members m where m.family_id=p_family_id and m.user_id=auth.uid() and m.is_active) $$;

create or replace function public.app_is_family_admin(p_family_id uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp
as $$ select exists (select 1 from public.family_members m where m.family_id=p_family_id and m.user_id=auth.uid() and m.role='admin' and m.is_active) $$;

create or replace function public.create_family(p_name text, p_display_name text)
returns uuid language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_user uuid := auth.uid(); v_family uuid;
begin
  if v_user is null then raise exception 'Sign in first'; end if;
  if length(trim(coalesce(p_name,''))) < 2 or length(trim(coalesce(p_display_name,''))) < 1 then raise exception 'Family and member names are required'; end if;
  insert into public.families(name, created_by) values (trim(p_name), v_user) returning id into v_family;
  insert into public.family_members(family_id,user_id,display_name,role) values (v_family,v_user,trim(p_display_name),'admin');
  return v_family;
end $$;

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

create or replace function public.create_weekly_plan(p_family_id uuid, p_week_start date default null)
returns uuid language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_start date := coalesce(p_week_start, date_trunc('week', now() at time zone 'Europe/Stockholm')::date); v_id uuid;
begin
  if not public.app_is_family_admin(p_family_id) then raise exception 'Only family admins can create the weekly plan'; end if;
  if extract(isodow from v_start) <> 1 then raise exception 'Week must start on Monday'; end if;
  if v_start < date_trunc('week', now() at time zone 'Europe/Stockholm')::date then raise exception 'Cannot create a past weekly plan'; end if;
  insert into public.weekly_plans(family_id,week_start,created_by) values(p_family_id,v_start,auth.uid()) on conflict(family_id,week_start) do update set family_id=excluded.family_id returning id into v_id;
  return v_id;
end $$;

create or replace function public.add_weekly_chore(p_plan_id uuid,p_title text,p_description text,p_xp integer,p_tokens integer,p_assignees uuid[])
returns uuid language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_plan public.weekly_plans%rowtype; v_chore uuid; v_member uuid;
begin
  select * into v_plan from public.weekly_plans where id=p_plan_id for update;
  if not found or not public.app_is_family_admin(v_plan.family_id) then raise exception 'Weekly plan not found or admin access required'; end if;
  if v_plan.status <> 'open' then raise exception 'This weekly plan is closed'; end if;
  if length(trim(coalesce(p_title,''))) < 1 or coalesce(array_length(p_assignees,1),0)=0 then raise exception 'Title and at least one assignee are required'; end if;
  if p_xp < 0 or p_xp > 500 or p_tokens < 0 or p_tokens > 100 then raise exception 'Invalid rewards'; end if;
  foreach v_member in array p_assignees loop
    if not exists(select 1 from public.family_members where family_id=v_plan.family_id and user_id=v_member and is_active) then raise exception 'Every assignee must be an active member of this family'; end if;
  end loop;
  insert into public.chores(family_id,plan_id,title,description,xp_reward,token_reward,created_by)
  values(v_plan.family_id,v_plan.id,trim(p_title),coalesce(trim(p_description),''),p_xp,p_tokens,auth.uid()) returning id into v_chore;
  insert into public.chore_assignments(family_id,chore_id,user_id,assigned_by)
  select v_plan.family_id,v_chore,distinct_user,auth.uid() from (select distinct unnest(p_assignees) as distinct_user) a;
  return v_chore;
end $$;

create or replace function public.submit_chore(p_chore_id uuid)
returns uuid language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_chore public.chores%rowtype; v_submission uuid;
begin
  select * into v_chore from public.chores where id=p_chore_id and is_active for update;
  if not found then raise exception 'Chore not found'; end if;
  if not public.app_is_family_member(v_chore.family_id) then raise exception 'Family access required'; end if;
  if not exists(select 1 from public.chore_assignments where chore_id=v_chore.id and user_id=auth.uid()) then raise exception 'This chore is not assigned to you'; end if;
  if v_chore.kind='weekly' then
    if exists(select 1 from public.chores where family_id=v_chore.family_id and kind='curse' and resolved_at is null) then raise exception 'Resolve active curses first'; end if;
    if not exists(select 1 from public.weekly_plans where id=v_chore.plan_id and status='open') then raise exception 'Weekly plan is closed'; end if;
  end if;
  if exists(select 1 from public.quest_submissions where chore_id=v_chore.id and user_id=auth.uid() and status='approved') then raise exception 'This chore is already approved'; end if;
  insert into public.quest_submissions(family_id,chore_id,user_id,xp_reward,token_reward)
  values(v_chore.family_id,v_chore.id,auth.uid(),case when v_chore.kind='curse' then 0 else v_chore.xp_reward end,case when v_chore.kind='curse' then 0 else v_chore.token_reward end)
  returning id into v_submission;
  return v_submission;
end $$;

create or replace function public.decide_quest_submission(p_submission_id uuid,p_decision text,p_reason text default '')
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_sub public.quest_submissions%rowtype; v_chore public.chores%rowtype; v_admin_name text;
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
    update public.family_members set xp=xp+v_sub.xp_reward,tokens=tokens+v_sub.token_reward where family_id=v_sub.family_id and user_id=v_sub.user_id;
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

alter table public.families enable row level security;
alter table public.family_members enable row level security;
alter table public.family_invites enable row level security;
alter table public.weekly_plans enable row level security;
alter table public.chores enable row level security;
alter table public.chore_assignments enable row level security;
alter table public.quest_submissions enable row level security;
alter table public.weekly_rewards enable row level security;
alter table public.notifications enable row level security;

drop policy if exists families_read_members on public.families;
create policy families_read_members on public.families for select to authenticated using (public.app_is_family_member(id));
drop policy if exists family_members_read_family on public.family_members;
create policy family_members_read_family on public.family_members for select to authenticated using (public.app_is_family_member(family_id));
drop policy if exists invites_admin_read on public.family_invites;
create policy invites_admin_read on public.family_invites for select to authenticated using (public.app_is_family_admin(family_id));
drop policy if exists weekly_plans_read_family on public.weekly_plans;
create policy weekly_plans_read_family on public.weekly_plans for select to authenticated using (public.app_is_family_member(family_id));
drop policy if exists chores_read_family on public.chores;
create policy chores_read_family on public.chores for select to authenticated using (public.app_is_family_member(family_id));
drop policy if exists assignments_read_family on public.chore_assignments;
create policy assignments_read_family on public.chore_assignments for select to authenticated using (public.app_is_family_member(family_id));
drop policy if exists submissions_read_family on public.quest_submissions;
create policy submissions_read_family on public.quest_submissions for select to authenticated using (public.app_is_family_member(family_id));
drop policy if exists weekly_rewards_read_family on public.weekly_rewards;
create policy weekly_rewards_read_family on public.weekly_rewards for select to authenticated using (public.app_is_family_member(family_id));
drop policy if exists notifications_read_self on public.notifications;
create policy notifications_read_self on public.notifications for select to authenticated using (user_id=auth.uid() and public.app_is_family_member(family_id));

revoke all on public.families,public.family_members,public.family_invites,public.weekly_plans,public.chores,public.chore_assignments,public.quest_submissions,public.weekly_rewards,public.notifications from anon,authenticated;
grant select on public.families,public.family_members,public.family_invites,public.weekly_plans,public.chores,public.chore_assignments,public.quest_submissions,public.weekly_rewards,public.notifications to authenticated;
revoke all on function public.app_is_family_member(uuid),public.app_is_family_admin(uuid),public.create_family(text,text),public.create_family_invite(uuid,text),public.join_family(text,text),public.create_weekly_plan(uuid,date),public.add_weekly_chore(uuid,text,text,integer,integer,uuid[]),public.submit_chore(uuid),public.decide_quest_submission(uuid,text,text),public.close_weekly_plan(uuid) from public,anon;
grant execute on function public.app_is_family_member(uuid),public.app_is_family_admin(uuid),public.create_family(text,text),public.create_family_invite(uuid,text),public.join_family(text,text),public.create_weekly_plan(uuid,date),public.add_weekly_chore(uuid,text,text,integer,integer,uuid[]),public.submit_chore(uuid),public.decide_quest_submission(uuid,text,text),public.close_weekly_plan(uuid) to authenticated;

grant usage on schema public to authenticated;
