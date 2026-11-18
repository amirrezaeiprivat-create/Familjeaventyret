-- Safe family exit, member role changes/removal, and admin-only family deletion.
create or replace function public.leave_family(p_family_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_member public.family_members%rowtype; v_admins integer;
begin
  perform 1 from public.families where id=p_family_id for update;
  if not found then raise exception 'Family not found'; end if;
  select * into v_member from public.family_members
  where family_id=p_family_id and user_id=auth.uid() and is_active for update;
  if not found then raise exception 'You are not an active member of this family'; end if;
  if v_member.role='admin' then
    select count(*) into v_admins from public.family_members where family_id=p_family_id and role='admin' and is_active;
    if v_admins <= 1 then raise exception 'This family needs an administrator. Add another admin or delete the family instead.'; end if;
  end if;
  delete from public.chore_assignments where family_id=p_family_id and user_id=auth.uid();
  delete from public.family_members where family_id=p_family_id and user_id=auth.uid();
end $$;

create or replace function public.admin_set_member_role(p_family_id uuid,p_user_id uuid,p_role text)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_target public.family_members%rowtype; v_admins integer;
begin
  if not public.app_is_family_admin(p_family_id) then raise exception 'Only a family admin can change roles'; end if;
  if p_role not in ('admin','player') then raise exception 'Invalid family role'; end if;
  perform 1 from public.families where id=p_family_id for update;
  if not public.app_is_family_admin(p_family_id) then raise exception 'Only a family admin can change roles'; end if;
  select * into v_target from public.family_members where family_id=p_family_id and user_id=p_user_id and is_active for update;
  if not found then raise exception 'Family member not found'; end if;
  select count(*) into v_admins from public.family_members where family_id=p_family_id and role='admin' and is_active;
  if p_role='admin' and v_target.role<>'admin' and v_admins>=2 then raise exception 'A family can have at most two active administrators'; end if;
  if p_role='player' and v_target.role='admin' and v_admins<=1 then raise exception 'A family must keep at least one active administrator'; end if;
  update public.family_members set role=p_role where family_id=p_family_id and user_id=p_user_id;
end $$;

create or replace function public.admin_remove_family_member(p_family_id uuid,p_user_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_target public.family_members%rowtype; v_admins integer;
begin
  if not public.app_is_family_admin(p_family_id) then raise exception 'Only a family admin can remove members'; end if;
  if p_user_id=auth.uid() then raise exception 'Use Leave family to remove yourself'; end if;
  perform 1 from public.families where id=p_family_id for update;
  if not public.app_is_family_admin(p_family_id) then raise exception 'Only a family admin can remove members'; end if;
  select * into v_target from public.family_members where family_id=p_family_id and user_id=p_user_id and is_active for update;
  if not found then raise exception 'Family member not found'; end if;
  if v_target.role='admin' then
    select count(*) into v_admins from public.family_members where family_id=p_family_id and role='admin' and is_active;
    if v_admins<=1 then raise exception 'A family must keep at least one active administrator'; end if;
  end if;
  delete from public.chore_assignments where family_id=p_family_id and user_id=p_user_id;
  delete from public.family_members where family_id=p_family_id and user_id=p_user_id;
end $$;

create or replace function public.admin_delete_family(p_family_id uuid)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  perform 1 from public.families where id=p_family_id for update;
  if not found then raise exception 'Family not found'; end if;
  if not public.app_is_family_admin(p_family_id) then raise exception 'Only a family admin can delete this family'; end if;
  delete from public.families where id=p_family_id;
end $$;

revoke all on function public.leave_family(uuid),public.admin_set_member_role(uuid,uuid,text),public.admin_remove_family_member(uuid,uuid),public.admin_delete_family(uuid) from public,anon;
grant execute on function public.leave_family(uuid),public.admin_set_member_role(uuid,uuid,text),public.admin_remove_family_member(uuid,uuid),public.admin_delete_family(uuid) to authenticated;
notify pgrst, 'reload schema';
