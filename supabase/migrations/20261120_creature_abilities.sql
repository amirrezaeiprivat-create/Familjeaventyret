-- Server-validated powers, requests, progression, and activation history.
alter table public.creature_inventory add column if not exists consumed_at timestamptz;
alter table public.chore_assignments add column if not exists deadline_at timestamptz;

create table if not exists public.creature_ability_catalog (
  creature_id text primary key references public.creature_catalog(creature_id) on delete cascade,
  effect_key text not null,
  cooldown_hours integer not null check (cooldown_hours >= 0),
  min_level integer not null default 1 check (min_level between 1 and 5),
  consumes_on_use boolean not null default false,
  config jsonb not null default '{}'::jsonb
);

insert into public.creature_ability_catalog(creature_id,effect_key,cooldown_hours,min_level,consumes_on_use,config) values
('dusty','remove_easy_once',0,1,true,'{}'),('puddle','bonus_easy_tokens',24,1,false,'{"tokens":2}'),('nibble','streak_shield',168,1,false,'{"uses":1}'),('pip','quest_hint',24,1,false,'{}'),('shelly','extend_easy_deadline',48,1,false,'{"hours":24}'),('bristle','streak_shield',120,1,false,'{"uses":1}'),('acorn','grant_creature_xp',48,1,false,'{"xp":20}'),('misty','reveal_task_detail',24,1,false,'{}'),('pebble','bonus_next_tokens',72,1,false,'{"tokens":3}'),('echo','task_reminder',24,1,false,'{}'),('cloudy','deadline_grace',72,1,false,'{}'),('flutter','creature_xp_next',48,1,false,'{"xp":10}'),('mossy','creature_xp_easy',48,1,false,'{"xp":15}'),('clack','token_shield',72,1,false,'{"uses":1}'),('tumble','extend_easy_deadline',96,1,false,'{"hours":24}'),
('flicker','remove_easy_repeat',48,1,false,'{}'),('bandit','bonus_after_two',48,1,false,'{"tokens":3}'),('wisp','quest_hint',48,1,false,'{}'),('fern','creature_xp_target_next',48,1,false,'{"xp":15}'),('buzz','creature_xp_ontime',48,1,false,'{"xp":10}'),('howler','family_challenge',96,2,false,'{"goal":10,"days":7}'),('ripple','request_transfer_easy',72,2,false,'{}'),('glimmer','best_reward_hint',48,1,false,'{}'),('chestnut','bonus_shards_next_chest',72,1,false,'{"shards":5,"chance":0.25}'),('jolly','boss_progress_bonus',72,1,false,'{"progress":2}'),('pebblehorn','extend_medium_deadline',72,1,false,'{"hours":24}'),('slink','swap_easy',72,1,false,'{}'),
('ember','creature_xp_hard',96,1,false,'{"xp":20}'),('skyrush','remove_easy_or_request_medium',96,2,false,'{}'),('moonhart','creature_xp_target_next',72,1,false,'{"xp":20}'),('boulder','medium_reward_shield',96,1,false,'{"uses":1}'),('marina','bonus_medium_tokens',96,1,false,'{"tokens":5}'),('shadowpaw','request_transfer_easy_medium',96,2,false,'{}'),('crystalwing','creature_xp_weekly',96,1,false,'{"xp":15}'),('tideback','streak_shield_plus',120,1,false,'{"uses":2}'),('venom','bonus_hard_tokens',96,1,false,'{"tokens":5}'),('frosthorn','bonus_easy_creature_xp',96,1,false,'{"xp":15,"tokens":2}'),
('inferno','remove_easy_medium',144,2,false,'{}'),('lunara','creature_xp_hard',144,1,false,'{"xp":20}'),('volt','boss_progress_bonus',120,1,false,'{"progress":3}'),('elderroot','streak_shield_plus',168,1,false,'{"uses":2}'),('glacius','request_remove_medium',144,2,false,'{}'),('prism','bonus_duplicate_shards',120,1,false,'{"shards":10}'),('dreamweaver','creature_xp_daily',168,1,false,'{"xp":10,"hours":24}'),('tricksy','request_transfer_easy_medium',168,2,false,'{}'),
('aureon','free_wooden_chest',168,1,false,'{}'),('solstice','creature_xp_hard_big',240,3,false,'{"xp":35}'),('titan','request_remove_medium_streak',240,3,false,'{"uses":1}'),('celestia','bonus_next_chest',288,1,false,'{"shards":5}'),('voidstar','free_chest_shards',336,3,false,'{"shards":5}')
on conflict(creature_id) do update set effect_key=excluded.effect_key,cooldown_hours=excluded.cooldown_hours,min_level=excluded.min_level,consumes_on_use=excluded.consumes_on_use,config=excluded.config;

create table if not exists public.creature_ability_logs (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, creature_instance_id uuid not null references public.creature_inventory(id) on delete cascade,
  effect_key text not null, request_key uuid not null, result text not null check(result in ('applied','pending_admin','rejected')),
  result_detail jsonb not null default '{}'::jsonb, created_at timestamptz not null default now(), unique(user_id,request_key)
);
create table if not exists public.creature_ability_requests (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
  requester_id uuid not null references auth.users(id), creature_instance_id uuid not null references public.creature_inventory(id) on delete cascade,
  effect_key text not null, request_type text not null check(request_type in ('remove','transfer','deadline_grace')),
  chore_id uuid not null references public.chores(id), target_user_id uuid references auth.users(id),
  status text not null default 'pending' check(status in ('pending','approved','rejected')),
  decided_by uuid references auth.users(id), decided_at timestamptz, decision_reason text not null default '',
  created_at timestamptz not null default now()
);
create table if not exists public.family_challenges (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
  title text not null, goal integer not null default 10, progress integer not null default 0,
  status text not null default 'active' check(status in ('active','complete','expired')),
  starts_at timestamptz not null default now(), ends_at timestamptz not null default now()+interval '7 days', created_by uuid not null references auth.users(id)
);
create table if not exists public.creature_chest_credits (
  id uuid primary key default gen_random_uuid(), family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade, chest_type text not null check(chest_type in ('wooden','silver','gold','diamond')),
  source text not null, created_at timestamptz not null default now(), redeemed_at timestamptz
);

alter table public.creature_ability_catalog enable row level security;
alter table public.creature_ability_logs enable row level security;
alter table public.creature_ability_requests enable row level security;
alter table public.family_challenges enable row level security;
alter table public.creature_chest_credits enable row level security;
drop policy if exists ability_logs_read_self on public.creature_ability_logs;
create policy ability_logs_read_self on public.creature_ability_logs for select to authenticated using(user_id=auth.uid() and public.app_is_family_member(family_id));
drop policy if exists ability_requests_read_family on public.creature_ability_requests;
create policy ability_requests_read_family on public.creature_ability_requests for select to authenticated using(public.app_is_family_member(family_id));
drop policy if exists family_challenges_read_family on public.family_challenges;
create policy family_challenges_read_family on public.family_challenges for select to authenticated using(public.app_is_family_member(family_id));
drop policy if exists creature_chest_credits_read_self on public.creature_chest_credits;
create policy creature_chest_credits_read_self on public.creature_chest_credits for select to authenticated using(user_id=auth.uid() and public.app_is_family_member(family_id));
revoke all on public.creature_ability_catalog,public.creature_ability_logs,public.creature_ability_requests,public.family_challenges,public.creature_chest_credits from public,anon,authenticated;
grant select on public.creature_ability_logs,public.creature_ability_requests,public.family_challenges,public.creature_chest_credits to authenticated;
do $$ begin
  alter publication supabase_realtime add table public.creature_ability_requests;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.family_challenges;
exception when duplicate_object then null; when undefined_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.creature_chest_credits;
exception when duplicate_object then null; when undefined_object then null; end $$;

create or replace function public.use_creature_ability(p_family_id uuid,p_creature_instance_id uuid,p_request_key uuid,p_target_chore_id uuid default null,p_secondary_chore_id uuid default null,p_target_creature_id uuid default null,p_target_user_id uuid default null)
returns jsonb language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_member public.family_members%rowtype; v_creature public.creature_inventory%rowtype; v_rule public.creature_ability_catalog%rowtype; v_chore public.chores%rowtype; v_effect_id uuid; v_request_id uuid; v_log jsonb; v_result text:='applied'; v_text text:='Förmågan aktiverades.'; v_now timestamptz:=now(); v_deadline timestamptz;
begin
  if auth.uid() is null then raise exception 'Sign in is required'; end if;
  if p_request_key is null then raise exception 'Request key is required'; end if;
  select * into v_member from public.family_members where family_id=p_family_id and user_id=auth.uid() and is_active for update;
  if not found then raise exception 'Active family membership required'; end if;
  select result_detail into v_log from public.creature_ability_logs where user_id=auth.uid() and request_key=p_request_key;
  if found then return v_log; end if;
  select * into v_creature from public.creature_inventory where id=p_creature_instance_id and family_id=p_family_id and user_id=auth.uid() and not is_cursed for update;
  if not found then raise exception 'That creature does not belong to you'; end if;
  if v_creature.consumed_at is not null then raise exception 'This creature has already been consumed'; end if;
  select * into v_rule from public.creature_ability_catalog where creature_id=v_creature.creature_id;
  if not found then raise exception 'This creature has no configured ability'; end if;
  if v_creature.level<v_rule.min_level then raise exception 'This ability unlocks at creature level %',v_rule.min_level; end if;
  if v_creature.cooldown_until is not null and v_creature.cooldown_until>v_now then raise exception 'Ability is on cooldown until %',v_creature.cooldown_until; end if;
  if v_rule.effect_key in ('remove_easy_once','remove_easy_repeat','remove_easy_or_request_medium','remove_easy_medium','request_remove_medium','request_remove_medium_streak','extend_easy_deadline','extend_medium_deadline','swap_easy','request_transfer_easy','request_transfer_easy_medium','deadline_grace') then
    select * into v_chore from public.chores where id=p_target_chore_id and family_id=p_family_id and is_active for update;
    if not found or not exists(select 1 from public.chore_assignments a where a.chore_id=v_chore.id and a.user_id=auth.uid()) then raise exception 'Choose a task assigned to you'; end if;
    if v_chore.kind<>'weekly' then raise exception 'Curse tasks cannot be changed by creature abilities'; end if;
    if exists(select 1 from public.quest_submissions s where s.chore_id=v_chore.id and s.user_id=auth.uid() and s.status in ('pending_approval','approved')) then raise exception 'This task has already been submitted'; end if;
  end if;
  if v_rule.effect_key in ('remove_easy_once','remove_easy_repeat','extend_easy_deadline') and v_chore.difficulty<>'Lätt' then raise exception 'Choose an easy task'; end if;
  if v_rule.effect_key='extend_medium_deadline' and v_chore.difficulty<>'Mellan' then raise exception 'Choose a medium task'; end if;
  if v_rule.effect_key in ('request_remove_medium','request_remove_medium_streak') and v_chore.difficulty<>'Mellan' then raise exception 'Choose a medium task'; end if;
  if v_rule.effect_key='deadline_grace' then
    select coalesce(a.deadline_at,v_chore.deadline_at) into v_deadline from public.chore_assignments a where a.chore_id=v_chore.id and a.user_id=auth.uid();
    if v_deadline is null or v_deadline>=v_now then raise exception 'This task deadline has not passed yet'; end if;
  end if;
  if v_rule.effect_key='remove_easy_or_request_medium' and v_chore.difficulty not in ('Lätt','Mellan') then raise exception 'Choose an easy or medium task'; end if;
  if v_rule.effect_key in ('remove_easy_medium','request_remove_medium','request_remove_medium_streak') and v_chore.difficulty not in ('Lätt','Mellan') then raise exception 'Choose an easy or medium task'; end if;
  if v_rule.effect_key in ('request_remove_medium','request_remove_medium_streak') or (v_rule.effect_key in ('remove_easy_or_request_medium','request_transfer_easy_medium') and v_chore.difficulty='Mellan' and v_rule.effect_key='remove_easy_or_request_medium') then
    insert into public.creature_ability_requests(family_id,requester_id,creature_instance_id,effect_key,request_type,chore_id)
    values(p_family_id,auth.uid(),v_creature.id,v_rule.effect_key,'remove',v_chore.id) returning id into v_request_id;
    v_result:='pending_admin'; v_text:='Begäran om borttagning skickades till en administratör.';
  elsif v_rule.effect_key in ('request_transfer_easy','request_transfer_easy_medium') then
    if p_target_user_id is null or p_target_user_id=auth.uid() or not exists(select 1 from public.family_members where family_id=p_family_id and user_id=p_target_user_id and is_active) or exists(select 1 from public.chore_assignments where chore_id=v_chore.id and user_id=p_target_user_id) then raise exception 'Choose another active family member who is not already assigned'; end if;
    if v_rule.effect_key='request_transfer_easy' and v_chore.difficulty<>'Lätt' then raise exception 'Choose an easy task'; end if;
    if v_rule.effect_key='request_transfer_easy_medium' and v_chore.difficulty not in ('Lätt','Mellan') then raise exception 'Choose an easy or medium task'; end if;
    insert into public.creature_ability_requests(family_id,requester_id,creature_instance_id,effect_key,request_type,chore_id,target_user_id)
    values(p_family_id,auth.uid(),v_creature.id,v_rule.effect_key,'transfer',v_chore.id,p_target_user_id) returning id into v_request_id;
    v_result:='pending_admin'; v_text:='Begäran om överföring skickades till en administratör.';
  elsif v_rule.effect_key in ('remove_easy_once','remove_easy_repeat','remove_easy_medium','remove_easy_or_request_medium') then
    if v_chore.difficulty<>'Lätt' and v_rule.effect_key in ('remove_easy_once','remove_easy_repeat') then raise exception 'Choose an easy task'; end if;
    if v_rule.effect_key='remove_easy_medium' and v_chore.difficulty not in ('Lätt','Mellan') then raise exception 'Choose an easy or medium task'; end if;
    delete from public.chore_assignments where chore_id=v_chore.id and user_id=auth.uid();
    v_text:='Uppgiften togs bort från din lista utan belöning.';
  elsif v_rule.effect_key in ('extend_easy_deadline','extend_medium_deadline') then
    update public.chore_assignments set deadline_at=greatest(coalesce(deadline_at,v_now),v_now)+make_interval(hours=>coalesce((v_rule.config->>'hours')::integer,24)) where chore_id=v_chore.id and user_id=auth.uid();
    v_text:='Du fick 24 timmar extra på uppgiften.';
  elsif v_rule.effect_key='deadline_grace' then
    insert into public.creature_ability_requests(family_id,requester_id,creature_instance_id,effect_key,request_type,chore_id)
    values(p_family_id,auth.uid(),v_creature.id,v_rule.effect_key,'deadline_grace',v_chore.id) returning id into v_request_id;
    v_result:='pending_admin'; v_text:='Begäran om extra inlämningsmöjlighet skickades till en administratör.';
  elsif v_rule.effect_key='swap_easy' then
    if v_chore.difficulty<>'Lätt' or p_secondary_chore_id is null then raise exception 'Choose an easy replacement task'; end if;
    if not exists(select 1 from public.chores c join public.weekly_plans p on p.id=c.plan_id where c.id=p_secondary_chore_id and c.family_id=p_family_id and c.kind='weekly' and c.is_active and c.difficulty='Lätt' and p.id=v_chore.plan_id and p.status='open' and not exists(select 1 from public.chore_assignments a where a.chore_id=c.id)) then raise exception 'That replacement task is not available'; end if;
    delete from public.chore_assignments where chore_id=v_chore.id and user_id=auth.uid();
    insert into public.chore_assignments(family_id,chore_id,user_id,assigned_by) values(p_family_id,p_secondary_chore_id,auth.uid(),auth.uid());
    v_text:='Uppgiften byttes mot en ledig lätt uppgift.';
  elsif v_rule.effect_key='grant_creature_xp' then
    if p_target_creature_id is null or p_target_creature_id=v_creature.id then raise exception 'Choose another creature in your collection'; end if;
    update public.creature_inventory set creature_xp=creature_xp+coalesce((v_rule.config->>'xp')::integer,20),level=least(5,1+((creature_xp+coalesce((v_rule.config->>'xp')::integer,20))/100)) where id=p_target_creature_id and family_id=p_family_id and user_id=auth.uid() and not is_cursed and consumed_at is null;
    if not found then raise exception 'Target creature is not active in your collection'; end if;
    v_text:='Varelsen fick Creature XP.';
  elsif v_rule.effect_key='creature_xp_target_next' then
    if p_target_creature_id is null or not exists(select 1 from public.creature_inventory where id=p_target_creature_id and family_id=p_family_id and user_id=auth.uid() and not is_cursed and consumed_at is null) then raise exception 'Choose an active creature in your collection'; end if;
    insert into public.creature_effects(family_id,user_id,creature_id,effect_key,payload,uses_remaining) values(p_family_id,auth.uid(),v_creature.id,v_rule.effect_key,v_rule.config||jsonb_build_object('target_creature_id',p_target_creature_id),1) returning id into v_effect_id;
    v_text:='Varelsen får Creature XP efter nästa godkända uppgift.';
  elsif v_rule.effect_key in ('quest_hint','reveal_task_detail','task_reminder','best_reward_hint') then
    select c.* into v_chore from public.chores c join public.chore_assignments a on a.chore_id=c.id where c.family_id=p_family_id and a.user_id=auth.uid() and c.kind='weekly' and c.is_active and not exists(select 1 from public.quest_submissions s where s.chore_id=c.id and s.user_id=auth.uid() and s.status in ('approved','pending_approval')) order by case when v_rule.effect_key='best_reward_hint' then c.token_reward end desc,case when v_rule.effect_key='task_reminder' then c.deadline_at end asc,c.created_at desc limit 1;
    if not found then raise exception 'There is no upcoming task to show'; end if;
    v_text:=case v_rule.effect_key when 'task_reminder' then 'Påminnelse: '||v_chore.title||case when v_chore.deadline_at is not null then ' · deadline '||to_char(v_chore.deadline_at,'DD Mon HH24:MI') else '' end when 'best_reward_hint' then 'Bästa myntbelöningen finns på: '||v_chore.title when 'reveal_task_detail' then 'Detalj: '||coalesce(nullif(v_chore.description,''),v_chore.title) else 'Ledtråd: nästa uppgift är '||v_chore.title end;
    insert into public.notifications(family_id,user_id,message) values(p_family_id,auth.uid(),v_text);
  elsif v_rule.effect_key='family_challenge' then
    insert into public.family_challenges(family_id,title,goal,created_by,ends_at) values(p_family_id,'Howlers familjeutmaning',10,auth.uid(),v_now+make_interval(days=>coalesce((v_rule.config->>'days')::integer,7)));
    v_text:='Familjens 7-dagarsutmaning startade: 10 godkända uppgifter tillsammans.';
  elsif v_rule.effect_key='boss_progress_bonus' then
    update public.family_challenges set progress=least(goal,progress+coalesce((v_rule.config->>'progress')::integer,1)),status=case when progress+coalesce((v_rule.config->>'progress')::integer,1)>=goal then 'complete' else status end where family_id=p_family_id and status='active' and ends_at>v_now;
    if not found then insert into public.family_challenges(family_id,title,goal,progress,status,created_by) values(p_family_id,'Familjens gemensamma utmaning',10,coalesce((v_rule.config->>'progress')::integer,1),'active',auth.uid()); end if;
    v_text:='Familjens gemensamma utmaning fick ett framsteg.';
  elsif v_rule.effect_key in ('free_wooden_chest','free_chest_shards') then
    insert into public.creature_chest_credits(family_id,user_id,chest_type,source) values(p_family_id,auth.uid(),'wooden',v_rule.effect_key) returning id into v_effect_id;
    if v_rule.effect_key='free_chest_shards' then insert into public.creature_effects(family_id,user_id,creature_id,effect_key,payload,uses_remaining) values(p_family_id,auth.uid(),v_creature.id,'bonus_next_chest',jsonb_build_object('shards',coalesce((v_rule.config->>'shards')::integer,5)),1); end if;
    v_text:='En kostnadsfri träkista lades till i dina belöningar.';
  else
    insert into public.creature_effects(family_id,user_id,creature_id,effect_key,payload,uses_remaining,expires_at)
    values(p_family_id,auth.uid(),v_creature.id,v_rule.effect_key,v_rule.config,case when v_rule.effect_key='creature_xp_daily' then 999 else coalesce((v_rule.config->>'uses')::integer,1) end,case when v_rule.effect_key='creature_xp_daily' then v_now+make_interval(hours=>coalesce((v_rule.config->>'hours')::integer,24)) else null end)
    returning id into v_effect_id;
    v_text:='Förmågan är aktiv och väntar på att utlösas av rätt uppgift.';
  end if;
  if v_rule.consumes_on_use then update public.creature_inventory set consumed_at=v_now where id=v_creature.id;
  else update public.creature_inventory set cooldown_until=v_now+make_interval(hours=>v_rule.cooldown_hours) where id=v_creature.id; end if;
  v_log:=jsonb_build_object('ok',true,'status',v_result,'message',v_text,'request_id',v_request_id,'effect_id',v_effect_id,'creature_name',v_creature.creature_name,'effect_key',v_rule.effect_key,'cooldown_until',case when not v_rule.consumes_on_use then v_now+make_interval(hours=>v_rule.cooldown_hours) else null end,'consumed',v_rule.consumes_on_use);
  insert into public.creature_ability_logs(family_id,user_id,creature_instance_id,effect_key,request_key,result,result_detail) values(p_family_id,auth.uid(),v_creature.id,v_rule.effect_key,p_request_key,v_result,v_log);
  return v_log;
exception when others then
  if auth.uid() is not null and p_request_key is not null
    and exists(select 1 from public.family_members where family_id=p_family_id and user_id=auth.uid() and is_active)
    and exists(select 1 from public.creature_inventory where id=p_creature_instance_id and family_id=p_family_id and user_id=auth.uid()) then
    insert into public.creature_ability_logs(family_id,user_id,creature_instance_id,effect_key,request_key,result,result_detail)
    values(p_family_id,auth.uid(),p_creature_instance_id,coalesce(v_rule.effect_key,'unknown'),p_request_key,'rejected',jsonb_build_object('ok',false,'status','rejected','message',sqlerrm))
    on conflict(user_id,request_key) do nothing;
  end if;
  return jsonb_build_object('ok',false,'status','rejected','message',sqlerrm);
end $$;

create or replace function public.decide_creature_ability_request(p_request_id uuid,p_decision text,p_reason text default '')
returns void language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_request public.creature_ability_requests%rowtype;
begin
  if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
  select * into v_request from public.creature_ability_requests where id=p_request_id for update;
  if not found or v_request.status<>'pending' then raise exception 'Request is no longer pending'; end if;
  if not public.app_is_family_admin(v_request.family_id) then raise exception 'Only a family admin can decide'; end if;
  if v_request.requester_id=auth.uid() then raise exception 'You cannot decide your own creature request'; end if;
  if p_decision='approved' and v_request.request_type in ('remove','transfer','deadline_grace') and not exists(select 1 from public.chores where id=v_request.chore_id and family_id=v_request.family_id and is_active and kind='weekly') then raise exception 'This task is no longer available'; end if;
  if p_decision='approved' and v_request.request_type in ('remove','transfer','deadline_grace') and not exists(select 1 from public.chore_assignments where chore_id=v_request.chore_id and user_id=v_request.requester_id) then raise exception 'The requester is no longer assigned to this task'; end if;
  if p_decision='approved' and v_request.request_type='transfer' and (not exists(select 1 from public.family_members where family_id=v_request.family_id and user_id=v_request.target_user_id and is_active) or exists(select 1 from public.chore_assignments where chore_id=v_request.chore_id and user_id=v_request.target_user_id)) then raise exception 'The selected family member can no longer receive this task'; end if;
  update public.creature_ability_requests set status=p_decision,decided_by=auth.uid(),decided_at=now(),decision_reason=left(trim(coalesce(p_reason,'')),500) where id=p_request_id;
  if p_decision='approved' then
    if v_request.request_type='remove' then
      delete from public.chore_assignments where chore_id=v_request.chore_id and user_id=v_request.requester_id;
      if v_request.effect_key='request_remove_medium_streak' then insert into public.creature_effects(family_id,user_id,creature_id,effect_key,payload,uses_remaining) values(v_request.family_id,v_request.requester_id,v_request.creature_instance_id,'streak_shield',jsonb_build_object('uses',1),1); end if;
    elsif v_request.request_type='transfer' then
      delete from public.chore_assignments where chore_id=v_request.chore_id and user_id=v_request.requester_id;
      insert into public.chore_assignments(family_id,chore_id,user_id,assigned_by) values(v_request.family_id,v_request.chore_id,v_request.target_user_id,auth.uid()) on conflict(chore_id,user_id) do nothing;
    else
      insert into public.creature_effects(family_id,user_id,creature_id,effect_key,payload,uses_remaining,expires_at)
      values(v_request.family_id,v_request.requester_id,v_request.creature_instance_id,'deadline_grace',jsonb_build_object('chore_id',v_request.chore_id),1,now()+interval '48 hours');
    end if;
  end if;
  insert into public.notifications(family_id,user_id,message) values(v_request.family_id,v_request.requester_id,case when p_decision='approved' then 'Din varelsebegäran godkändes.' else 'Din varelsebegäran nekades.'||case when trim(coalesce(p_reason,''))<>'' then ' Orsak: '||left(trim(p_reason),500) else '' end end);
end $$;

create or replace function public.apply_creature_effects_to_approved_quest()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_chore public.chores%rowtype; v_effect public.creature_effects%rowtype; v_deadline timestamptz; v_xp integer; v_tokens integer; v_target uuid; v_weekly_complete boolean;
begin
  if old.status<>'pending_approval' or new.status<>'approved' then return new; end if;
  select * into v_chore from public.chores where id=new.chore_id;
  if not found or v_chore.kind<>'weekly' then return new; end if;
  select coalesce(a.deadline_at,v_chore.deadline_at) into v_deadline from public.chore_assignments a where a.chore_id=v_chore.id and a.user_id=new.user_id;
  update public.family_challenges set progress=least(goal,progress+1),status=case when progress+1>=goal then 'complete' else status end where family_id=new.family_id and status='active' and ends_at>now();
  for v_effect in select * from public.creature_effects where family_id=new.family_id and user_id=new.user_id and starts_at<=now() and (expires_at is null or expires_at>now()) and uses_remaining>0 for update loop
    v_xp:=0; v_tokens:=0;
    if v_effect.effect_key='bonus_easy_tokens' and v_chore.difficulty='Lätt' then v_tokens:=coalesce((v_effect.payload->>'tokens')::integer,2);
    elsif v_effect.effect_key='bonus_next_tokens' then v_tokens:=coalesce((v_effect.payload->>'tokens')::integer,3);
    elsif v_effect.effect_key='bonus_after_two' and (select count(*) from public.quest_submissions s join public.chores c on c.id=s.chore_id where s.family_id=new.family_id and s.user_id=new.user_id and s.status='approved' and c.kind='weekly' and s.decided_at::date=(now() at time zone 'Europe/Stockholm')::date)>=2 then v_tokens:=coalesce((v_effect.payload->>'tokens')::integer,3);
    elsif v_effect.effect_key='bonus_medium_tokens' and v_chore.difficulty='Mellan' then v_tokens:=coalesce((v_effect.payload->>'tokens')::integer,5);
    elsif v_effect.effect_key='bonus_hard_tokens' and v_chore.difficulty='Svår' then v_tokens:=coalesce((v_effect.payload->>'tokens')::integer,5);
    elsif v_effect.effect_key='bonus_easy_creature_xp' and v_chore.difficulty='Lätt' then v_xp:=coalesce((v_effect.payload->>'xp')::integer,15); v_tokens:=coalesce((v_effect.payload->>'tokens')::integer,2);
    elsif v_effect.effect_key='creature_xp_next' then v_xp:=coalesce((v_effect.payload->>'xp')::integer,10);
    elsif v_effect.effect_key='creature_xp_easy' and v_chore.difficulty='Lätt' then v_xp:=coalesce((v_effect.payload->>'xp')::integer,15);
    elsif v_effect.effect_key='creature_xp_target_next' and (v_effect.payload->>'target_creature_id' is null or exists(select 1 from public.creature_inventory ci where ci.id=(v_effect.payload->>'target_creature_id')::uuid and ci.family_id=new.family_id and ci.user_id=new.user_id and not ci.is_cursed and ci.consumed_at is null)) then v_xp:=coalesce((v_effect.payload->>'xp')::integer,15);
    elsif v_effect.effect_key='creature_xp_ontime' and (v_deadline is null or new.submitted_at<=v_deadline) then v_xp:=coalesce((v_effect.payload->>'xp')::integer,10);
    elsif v_effect.effect_key='creature_xp_hard' and v_chore.difficulty='Svår' then v_xp:=coalesce((v_effect.payload->>'xp')::integer,20);
    elsif v_effect.effect_key='creature_xp_hard_big' and v_chore.difficulty='Svår' then v_xp:=coalesce((v_effect.payload->>'xp')::integer,35);
    elsif v_effect.effect_key='creature_xp_weekly' then
      select not exists(select 1 from public.chore_assignments a join public.chores c on c.id=a.chore_id and c.kind='weekly' and c.is_active left join public.quest_submissions s on s.chore_id=a.chore_id and s.user_id=a.user_id and s.status='approved' where c.plan_id=v_chore.plan_id and a.user_id=new.user_id and s.id is null) into v_weekly_complete;
      if v_weekly_complete then v_xp:=coalesce((v_effect.payload->>'xp')::integer,15); end if;
    elsif v_effect.effect_key='creature_xp_daily' then v_xp:=coalesce((v_effect.payload->>'xp')::integer,10);
    end if;
    if v_xp>0 then
      v_target:=nullif(v_effect.payload->>'target_creature_id','')::uuid;
      if v_target is null then v_target:=v_effect.creature_id; end if;
      if v_target is not null then update public.creature_inventory set creature_xp=creature_xp+v_xp,level=least(5,1+((creature_xp+v_xp)/100)) where id=v_target and family_id=new.family_id and user_id=new.user_id; end if;
    end if;
    if v_tokens>0 then update public.family_members set tokens=tokens+v_tokens where family_id=new.family_id and user_id=new.user_id; end if;
    if v_effect.effect_key<>'creature_xp_daily' and (v_xp>0 or v_tokens>0) then update public.creature_effects set uses_remaining=uses_remaining-1 where id=v_effect.id; end if;
  end loop;
  return new;
end $$;
drop trigger if exists creature_effects_on_quest_approval on public.quest_submissions;
create trigger creature_effects_on_quest_approval after update of status on public.quest_submissions for each row execute function public.apply_creature_effects_to_approved_quest();

create or replace function public.decide_quest_submission(p_submission_id uuid,p_decision text,p_reason text default '')
returns void language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_sub public.quest_submissions%rowtype; v_chore public.chores%rowtype; v_admin_name text; v_today date:=(now() at time zone 'Europe/Stockholm')::date; v_shield public.creature_effects%rowtype; v_previous_streak_date date; v_keep_streak boolean:=false;
begin
  if p_decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
  select * into v_sub from public.quest_submissions where id=p_submission_id for update;
  if not found or v_sub.status<>'pending_approval' then raise exception 'Submission is no longer pending'; end if;
  if not public.app_is_family_admin(v_sub.family_id) then raise exception 'Only a family admin can decide submissions'; end if;
  if v_sub.user_id=auth.uid() then raise exception 'You cannot decide your own submission'; end if;
  select * into v_chore from public.chores where id=v_sub.chore_id for update;
  select display_name into v_admin_name from public.family_members where family_id=v_sub.family_id and user_id=auth.uid();
  update public.quest_submissions set status=p_decision,decided_by=auth.uid(),decided_at=now(),rejection_reason=case when p_decision='rejected' then left(trim(coalesce(p_reason,'')),500) else '' end,rewarded_at=case when p_decision='approved' and v_chore.kind='weekly' then now() else null end where id=v_sub.id;
  if v_chore.kind='curse' then
    if p_decision='approved' then update public.chores set resolved_at=now() where id=v_chore.id; end if;
  elsif p_decision='approved' then
    select * into v_shield from public.creature_effects where family_id=v_sub.family_id and user_id=v_sub.user_id and effect_key in ('streak_shield','streak_shield_plus') and uses_remaining>0 and starts_at<=now() and (expires_at is null or expires_at>now()) order by created_at limit 1 for update;
    select last_streak_date into v_previous_streak_date from public.family_members where family_id=v_sub.family_id and user_id=v_sub.user_id;
    v_keep_streak:=v_shield.id is not null and v_previous_streak_date is not null and v_previous_streak_date<v_today-1;
    update public.family_members set xp=xp+v_sub.xp_reward,tokens=tokens+v_sub.token_reward,streak=case when last_streak_date=v_today then streak when last_streak_date=v_today-1 then streak+1 when v_keep_streak then streak else 1 end,last_streak_date=v_today where family_id=v_sub.family_id and user_id=v_sub.user_id;
    if v_keep_streak then update public.creature_effects set uses_remaining=uses_remaining-1 where id=v_shield.id; end if;
  end if;
  insert into public.notifications(family_id,user_id,message) values(v_sub.family_id,v_sub.user_id,case when p_decision='approved' then v_chore.title||' godkändes av '||coalesce(v_admin_name,'en administratör')||'.' else v_chore.title||' nekades.'||case when trim(coalesce(p_reason,''))<>'' then ' Anledning: '||left(trim(p_reason),500) else '' end end);
end $$;

revoke all on function public.apply_creature_effects_to_approved_quest() from public,anon,authenticated;
revoke all on function public.decide_quest_submission(uuid,text,text) from public,anon;
grant execute on function public.decide_quest_submission(uuid,text,text) to authenticated;

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
    if not exists(select 1 from public.weekly_plans where id=v_chore.plan_id and status='open') then raise exception 'Weekly plan is closed'; end if;
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

create or replace function public.open_creature_chest(p_family_id uuid,p_chest_type text,p_request_key uuid,p_credit_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_member public.family_members%rowtype; v_credit public.creature_chest_credits%rowtype; v_cost integer; v_chance numeric; v_pick public.creature_catalog%rowtype; v_existing jsonb; v_dup boolean:=false; v_shards integer:=0; v_bonus_shards integer:=0; v_chore uuid; v_opening uuid; v_inserted integer; v_active_curses integer; v_shield public.creature_effects%rowtype; v_bonus public.creature_effects%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in is required'; end if;
  if p_request_key is null then raise exception 'An idempotency key is required'; end if;
  if p_chest_type not in ('wooden','silver','gold','diamond') then raise exception 'Unknown chest type'; end if;
  v_cost:=case p_chest_type when 'wooden' then 35 when 'silver' then 70 when 'gold' then 110 else 160 end;
  select * into v_member from public.family_members where family_id=p_family_id and user_id=auth.uid() and is_active for update;
  if not found then raise exception 'Active family membership required'; end if;
  select result into v_existing from public.creature_chest_openings where user_id=auth.uid() and request_key=p_request_key;
  if found then if v_existing is null then raise exception 'Chest opening is already processing'; end if; return v_existing; end if;
  insert into public.creature_chest_openings(family_id,user_id,request_key,chest_type) values(p_family_id,auth.uid(),p_request_key,p_chest_type) on conflict(user_id,request_key) do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then select result into v_existing from public.creature_chest_openings where user_id=auth.uid() and request_key=p_request_key; if v_existing is null then raise exception 'Chest opening is already processing'; end if; return v_existing; end if;
  select id into v_opening from public.creature_chest_openings where user_id=auth.uid() and request_key=p_request_key;
  if p_credit_id is not null then
    select * into v_credit from public.creature_chest_credits where id=p_credit_id and family_id=p_family_id and user_id=auth.uid() and chest_type=p_chest_type and redeemed_at is null for update;
    if not found then raise exception 'This chest credit is invalid or already used'; end if;
    update public.creature_chest_credits set redeemed_at=now() where id=v_credit.id;
    v_cost:=0;
  end if;
  if v_member.tokens<v_cost then raise exception 'Not enough coins for this chest'; end if;
  update public.family_members set tokens=tokens-v_cost where family_id=p_family_id and user_id=auth.uid();
  v_chance:=case p_chest_type when 'wooden' then 10 when 'silver' then 5 when 'gold' then 2 else 1 end;
  select count(*) into v_active_curses from public.chores where family_id=p_family_id and kind='curse' and resolved_at is null and is_active;
  if v_active_curses<3 and random()*100<v_chance then
    select c.* into v_pick from public.creature_catalog c where c.is_cursed and (case p_chest_type when 'wooden' then c.wooden_weight when 'silver' then c.silver_weight when 'gold' then c.gold_weight else c.diamond_weight end)>0 order by -ln(greatest(random(),0.000000001))/(case p_chest_type when 'wooden' then c.wooden_weight when 'silver' then c.silver_weight when 'gold' then c.gold_weight else c.diamond_weight end) limit 1;
  else
    select c.* into v_pick from public.creature_catalog c where not c.is_cursed order by -ln(greatest(random(),0.000000001))/(case c.rarity when 'Common' then 50.0/15 when 'Uncommon' then 25.0/12 when 'Rare' then 15.0/10 when 'Epic' then 8.0/8 else 2.0/5 end) limit 1;
  end if;
  if not found then raise exception 'Creature catalog is empty'; end if;
  if v_pick.is_cursed then
    insert into public.creature_inventory(family_id,user_id,creature_id,creature_name,rarity,is_cursed) values(p_family_id,auth.uid(),v_pick.creature_id,v_pick.creature_name,'Curse',true);
    insert into public.chores(family_id,kind,title,description,difficulty,xp_reward,token_reward,deadline_at,created_by) values(p_family_id,'curse',v_pick.creature_name,v_pick.curse_task,case when v_pick.creature_name='Dreadlord' then 'Svår' else 'Lätt' end,0,0,now()+make_interval(hours=>v_pick.deadline_hours),auth.uid()) returning id into v_chore;
    insert into public.chore_assignments(family_id,chore_id,user_id,assigned_by) values(p_family_id,v_chore,auth.uid(),auth.uid());
    if v_pick.steals_tokens>0 then
      select * into v_shield from public.creature_effects e where e.family_id=p_family_id and e.user_id=auth.uid() and e.effect_key in ('token_shield','medium_reward_shield') and e.uses_remaining>0 and (e.expires_at is null or e.expires_at>now()) and (e.effect_key='token_shield' or exists(select 1 from public.quest_submissions s join public.chores c on c.id=s.chore_id where s.family_id=p_family_id and s.user_id=auth.uid() and s.status='approved' and c.kind='weekly' and c.difficulty='Mellan')) order by e.created_at limit 1 for update;
      if found then update public.creature_effects set uses_remaining=uses_remaining-1 where id=v_shield.id;
      else update public.family_members set tokens=greatest(0,tokens-least(v_pick.steals_tokens,tokens)) where family_id=p_family_id and user_id=auth.uid(); end if;
    end if;
  else
    select exists(select 1 from public.creature_inventory where family_id=p_family_id and user_id=auth.uid() and creature_id=v_pick.creature_id and not is_cursed) into v_dup;
    if v_dup then v_shards:=case v_pick.rarity when 'Common' then 5 when 'Uncommon' then 10 when 'Rare' then 20 when 'Epic' then 35 else 50 end; end if;
    if not v_dup then insert into public.creature_inventory(family_id,user_id,creature_id,creature_name,rarity) values(p_family_id,auth.uid(),v_pick.creature_id,v_pick.creature_name,v_pick.rarity); end if;
  end if;
  for v_bonus in select * from public.creature_effects where family_id=p_family_id and user_id=auth.uid() and effect_key in ('bonus_shards_next_chest','bonus_next_chest','bonus_duplicate_shards') and uses_remaining>0 and (expires_at is null or expires_at>now()) order by created_at for update loop
    if v_bonus.effect_key='bonus_shards_next_chest' then if random()<coalesce((v_bonus.payload->>'chance')::numeric,.25) then v_bonus_shards:=v_bonus_shards+coalesce((v_bonus.payload->>'shards')::integer,5); end if; update public.creature_effects set uses_remaining=uses_remaining-1 where id=v_bonus.id;
    elsif v_bonus.effect_key='bonus_next_chest' then v_bonus_shards:=v_bonus_shards+coalesce((v_bonus.payload->>'shards')::integer,5); update public.creature_effects set uses_remaining=uses_remaining-1 where id=v_bonus.id;
    elsif v_bonus.effect_key='bonus_duplicate_shards' and v_dup then v_bonus_shards:=v_bonus_shards+coalesce((v_bonus.payload->>'shards')::integer,10); update public.creature_effects set uses_remaining=uses_remaining-1 where id=v_bonus.id; end if;
  end loop;
  v_shards:=v_shards+v_bonus_shards;
  if v_shards>0 then update public.family_members set shards=shards+v_shards where family_id=p_family_id and user_id=auth.uid(); end if;
  select jsonb_build_object('creature_id',v_pick.creature_id,'creature_name',v_pick.creature_name,'rarity',v_pick.rarity,'is_cursed',v_pick.is_cursed,'is_duplicate',v_dup,'shards_awarded',v_shards,'bonus_shards_awarded',v_bonus_shards,'free_chest',p_credit_id is not null,'curse_task',v_pick.curse_task,'deadline_hours',v_pick.deadline_hours,'tokens',m.tokens,'shards',m.shards) into v_existing from public.family_members m where m.family_id=p_family_id and m.user_id=auth.uid();
  update public.creature_chest_openings set result=v_existing where id=v_opening;
  return v_existing;
end $$;

revoke all on function public.submit_chore(uuid),public.open_creature_chest(uuid,text,uuid,uuid) from public,anon;
grant execute on function public.submit_chore(uuid),public.open_creature_chest(uuid,text,uuid,uuid) to authenticated;
revoke all on function public.use_creature_ability(uuid,uuid,uuid,uuid,uuid,uuid,uuid),public.decide_creature_ability_request(uuid,text,text) from public,anon;
grant execute on function public.use_creature_ability(uuid,uuid,uuid,uuid,uuid,uuid,uuid),public.decide_creature_ability_request(uuid,text,text) to authenticated;
notify pgrst,'reload schema';
