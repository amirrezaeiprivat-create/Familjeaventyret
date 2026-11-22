-- Permit family admins to decide submissions they sent themselves.
-- The row lock and pending-status check keep approvals idempotent.
create or replace function public.decide_quest_submission(p_submission_id uuid,p_decision text,p_reason text default '')
returns void language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_sub public.quest_submissions%rowtype; v_chore public.chores%rowtype; v_admin_name text; v_today date:=(now() at time zone 'Europe/Stockholm')::date; v_shield public.creature_effects%rowtype; v_previous_streak_date date; v_keep_streak boolean:=false;
begin
  if p_decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
  select * into v_sub from public.quest_submissions where id=p_submission_id for update;
  if not found or v_sub.status<>'pending_approval' then raise exception 'Submission is no longer pending'; end if;
  if not public.app_is_family_admin(v_sub.family_id) then raise exception 'Only a family admin can decide submissions'; end if;
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
revoke all on function public.decide_quest_submission(uuid,text,text) from public,anon;
grant execute on function public.decide_quest_submission(uuid,text,text) to authenticated;
