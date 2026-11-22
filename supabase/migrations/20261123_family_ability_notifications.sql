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
  insert into public.notifications (family_id, user_id, message)
  select p_family_id, recipient.user_id,
    format('%s använde %s. %s', v_member.display_name, v_creature.creature_name,
      case
        when v_result='applied' and v_rule.effect_key in ('remove_easy_once','remove_easy_repeat','remove_easy_medium','remove_easy_or_request_medium')
          then format('Sysslan ”%s” (%s) hoppades över utan belöning.', v_chore.title, lower(v_chore.difficulty))
        when v_text='Förmågan är aktiv och väntar på att utlösas av rätt uppgift.'
          then 'Kraften är aktiv: ' || case lower(v_creature.creature_name)
            when 'dusty' then 'Tar bort en lätt uppgift. Förbrukas efter användning.'
            when 'puddle' then 'Ger en liten bonus till nästa godkända lätta uppgift.'
            when 'nibble' then 'Skyddar en svit från att brytas en gång.'
            when 'pip' then 'Visar en ledtråd om en kommande specialuppgift.'
            when 'shelly' then 'Ger extra tid på en valfri lätt uppgift.'
            when 'bristle' then 'Skyddar en svit från att brytas en gång.'
            when 'acorn' then 'Ger Varelse-XP till en annan aktiv varelse.'
            when 'misty' then 'Visar en dold detalj om en kommande uppgift.'
            when 'pebble' then 'Ger en liten myntbonus efter en godkänd uppgift.'
            when 'echo' then 'Påminner om en olöst uppgift och dess deadline.'
            when 'cloudy' then 'Ger en extra möjlighet att lämna in en uppgift efter missad deadline, om en admin tillåter det.'
            when 'flutter' then 'Ger Varelse-XP efter en godkänd uppgift.'
            when 'mossy' then 'Ger extra Varelse-XP från en godkänd lätt uppgift.'
            when 'clack' then 'Skyddar en intjänad myntbelöning från negativ speleffekt.'
            when 'tumble' then 'Flyttar fram en lätt uppgifts deadline med en dag.'
            when 'flicker' then 'Tar bort en lätt uppgift utan att förbrukas.'
            when 'bandit' then 'Ger en liten myntbonus efter två godkända uppgifter samma dag.'
            when 'wisp' then 'Visar en extra ledtråd om en specialuppgift.'
            when 'fern' then 'Ger extra Varelse-XP till en vald aktiv varelse efter en godkänd uppgift.'
            when 'buzz' then 'Ger extra Varelse-XP när en uppgift slutförs i tid.'
            when 'howler' then 'Startar en familjeutmaning där alla kan bidra.'
            when 'ripple' then 'Skapar en begäran om att överföra en lätt uppgift till en annan familjemedlem. Kräver adminbeslut.'
            when 'glimmer' then 'Visar vilka kommande uppgifter som ger bäst myntbelöning.'
            when 'chestnut' then 'Ger en liten chans till extra skärvor vid nästa kistöppning.'
            when 'jolly' then 'Ger en liten bonus till familjens gemensamma bossframsteg.'
            when 'pebblehorn' then 'Ger extra tid på en mellansvår uppgift.'
            when 'slink' then 'Byter en tilldelad lätt uppgift mot en annan tillgänglig lätt uppgift, om reglerna tillåter det.'
            when 'ember' then 'Ger extra Varelse-XP efter en godkänd svår uppgift.'
            when 'skyrush' then 'Tar bort en lätt uppgift eller begär borttagning av en mellansvår uppgift.'
            when 'moonhart' then 'Ger bonus-Varelse-XP till en vald aktiv varelse efter en godkänd uppgift.'
            when 'boulder' then 'Skyddar belöningen från en mellansvår uppgift från negativ speleffekt.'
            when 'marina' then 'Ger en extra myntbelöning efter en godkänd mellansvår uppgift.'
            when 'shadowpaw' then 'Möjliggör begäran om överföring av en lätt eller mellansvår uppgift. Kräver adminbeslut.'
            when 'crystalwing' then 'Ger extra Varelse-XP när spelaren slutför en veckoutmaning.'
            when 'tideback' then 'Skyddar en svit och ger en extra återhämtningsmöjlighet.'
            when 'venom' then 'Ger en liten bonus till nästa godkända svåra uppgift.'
            when 'frosthorn' then 'Gör en lätt uppgift värd mer Varelse-XP och ger en liten myntbonus.'
            when 'inferno' then 'Tar bort en lätt eller mellansvår uppgift.'
            when 'lunara' then 'Ger extra Varelse-XP efter en godkänd svår uppgift.'
            when 'volt' then 'Ger en bonus till familjens gemensamma bossframsteg.'
            when 'elderroot' then 'Skyddar en svit och ger en extra återhämtningsmöjlighet.'
            when 'glacius' then 'Ger möjlighet att begära borttagning av en mellansvår uppgift.'
            when 'prism' then 'Ger extra skärvor när spelaren får en duplikatvarelse.'
            when 'dreamweaver' then 'Ger tillfällig Varelse-XP-bonus för godkända uppgifter under en dag.'
            when 'tricksy' then 'Begär överföring av en lätt eller mellansvår uppgift till en annan familjemedlem. Kräver adminbeslut.'
            when 'aureon' then 'Ger en gratis träkista.'
            when 'solstice' then 'Ger stor Varelse-XP-bonus efter en godkänd svår uppgift.'
            when 'titan' then 'Ger möjlighet att begära borttagning av en mellansvår uppgift och skyddar en svit.'
            when 'celestia' then 'Ger en bonus till nästa kista, exempelvis extra skärvor eller bättre kisttyp enligt reglerna.'
            when 'voidstar' then 'Ger en gratis kista och en mindre skärvbonus.'
            else v_text end
        else concat(case when p_target_chore_id is not null then format('Sysslan ”%s”: ', v_chore.title) end,
          replace(replace(replace(v_text, 'Du fick', 'Spelaren fick'), 'dina belöningar', 'spelarens belöningar'), 'din lista', 'spelarens lista'))
      end)
  from public.family_members recipient
  where recipient.family_id=p_family_id and recipient.is_active;
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

