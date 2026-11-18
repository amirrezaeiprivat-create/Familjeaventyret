-- Family admins can remove uncompleted weekly chores and grant coins to their own account.
create or replace function public.admin_delete_weekly_chore(p_chore_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_chore public.chores%rowtype;
begin
  if auth.uid() is null then raise exception 'Sign in is required'; end if;
  select * into v_chore from public.chores where id=p_chore_id and is_active and kind='weekly' for update;
  if not found or not public.app_is_family_admin(v_chore.family_id) then raise exception 'Weekly chore not found or admin access required'; end if;
  if not exists(select 1 from public.weekly_plans where id=v_chore.plan_id and family_id=v_chore.family_id and status='open') then raise exception 'Only chores in an open weekly plan can be removed'; end if;
  if exists(select 1 from public.quest_submissions where chore_id=v_chore.id and status='approved') then raise exception 'A chore with an approved submission cannot be removed'; end if;
  update public.quest_submissions
     set status='rejected',decided_by=auth.uid(),decided_at=now(),rejection_reason='Uppgiften togs bort av en administratör.',rewarded_at=null
   where chore_id=v_chore.id and status='pending_approval';
  update public.chores set is_active=false where id=v_chore.id;
  insert into public.notifications(family_id,user_id,message)
  select v_chore.family_id,a.user_id,'Sysslan '||v_chore.title||' togs bort av en administratör.'
    from public.chore_assignments a where a.chore_id=v_chore.id;
end;
$$;

create or replace function public.admin_grant_self_tokens(p_family_id uuid,p_amount integer)
returns integer language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_member public.family_members%rowtype; v_balance integer;
begin
  if auth.uid() is null then raise exception 'Sign in is required'; end if;
  if p_amount is null or p_amount<1 or p_amount>1000 then raise exception 'Coin amount must be between 1 and 1000'; end if;
  select * into v_member from public.family_members where family_id=p_family_id and user_id=auth.uid() and is_active for update;
  if not found or v_member.role<>'admin' then raise exception 'Only an active family admin can grant coins'; end if;
  update public.family_members set tokens=tokens+p_amount where family_id=p_family_id and user_id=auth.uid() returning tokens into v_balance;
  return v_balance;
end;
$$;

revoke all on function public.admin_delete_weekly_chore(uuid),public.admin_grant_self_tokens(uuid,integer) from public,anon;
grant execute on function public.admin_delete_weekly_chore(uuid),public.admin_grant_self_tokens(uuid,integer) to authenticated;
notify pgrst,'reload schema';
