-- Allow any number of administrators while keeping at least one active admin.
create or replace function public.create_family_invite(p_family_id uuid, p_role text)
returns text language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_code text;
  v_adjectives text[] := array['glad','snabb','lugn','modig','snäll','klok','busig','solig','mjuk','stark','liten','fin','vild','varm','pigg','grön'];
  v_nouns text[] := array['banan','klöver','kanel','stjärna','katt','bär','måne','skog','drake','moln','äng','räv','pärla','fjäril','äpple','vante'];
begin
  if not public.app_is_family_admin(p_family_id) then raise exception 'Only family admins can create invites'; end if;
  if p_role not in ('admin','player') then raise exception 'Invalid family role'; end if;
  loop
    v_code := v_adjectives[1+floor(random()*array_length(v_adjectives,1))::int] || '-' || v_nouns[1+floor(random()*array_length(v_nouns,1))::int];
    exit when not exists(select 1 from public.family_invites where invite_code=v_code and claimed_at is null and expires_at>now());
  end loop;
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
  select * into v_invite from public.family_invites where lower(invite_code)=lower(trim(p_invite_code)) and claimed_at is null and expires_at>now() for update;
  if not found then raise exception 'Invite code is invalid, expired, or already used'; end if;
  if exists(select 1 from public.family_members where user_id=v_user) then raise exception 'This account already belongs to a family'; end if;
  if v_invite.role='admin' then
    perform 1 from public.families where id=v_invite.family_id for update;
  end if;
  insert into public.family_members(family_id,user_id,display_name,role) values(v_invite.family_id,v_user,trim(p_display_name),v_invite.role);
  update public.family_invites set claimed_by=v_user,claimed_at=now() where id=v_invite.id;
  return v_invite.family_id;
end $$;

create or replace function public.admin_set_member_role(p_family_id uuid,p_user_id uuid,p_role text)
returns void language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_target public.family_members%rowtype;
begin
  if not public.app_is_family_admin(p_family_id) then raise exception 'Only a family admin can change roles'; end if;
  if p_role not in ('admin','player') then raise exception 'Invalid family role'; end if;
  perform 1 from public.families where id=p_family_id for update;
  if not public.app_is_family_admin(p_family_id) then raise exception 'Only a family admin can change roles'; end if;
  select * into v_target from public.family_members where family_id=p_family_id and user_id=p_user_id and is_active for update;
  if not found then raise exception 'Family member not found'; end if;
  if p_role='player' and v_target.role='admin' and v_admins<=1 then raise exception 'A family must keep at least one active administrator'; end if;
  update public.family_members set role=p_role where family_id=p_family_id and user_id=p_user_id;
end $$;

notify pgrst, 'reload schema';
