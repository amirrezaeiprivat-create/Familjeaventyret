-- Allow family admins to safely remove any creature from member collections.
  -- Soft removal preserves activation history and foreign-key references.
  alter table public.creature_inventory
    add column if not exists removed_at timestamptz,
    add column if not exists removed_by uuid references auth.users(id) on delete set null;

drop index if exists public.creature_inventory_active_family_idx;
create index creature_inventory_active_family_idx
    on public.creature_inventory(family_id, user_id)
  where removed_at is null;

drop function if exists public.admin_list_family_creatures(uuid);
  create or replace function public.admin_list_family_creatures(p_family_id uuid)
  returns table(
    id uuid,
    user_id uuid,
    display_name text,
    creature_name text,
    rarity text,
    level integer,
  creature_xp integer,
  is_cursed boolean
  )
  language plpgsql
  stable
  security definer
  set search_path = public, pg_temp
  as $$
  begin
    if auth.uid() is null or not public.app_is_family_admin(p_family_id) then
      raise exception 'Only a family admin can manage creature collections';
    end if;

    return query
  select ci.id, ci.user_id, fm.display_name, ci.creature_name, ci.rarity, ci.level, ci.creature_xp, ci.is_cursed
    from public.creature_inventory ci
    join public.family_members fm on fm.family_id=ci.family_id and fm.user_id=ci.user_id and fm.is_active
  where ci.family_id=p_family_id and ci.removed_at is null
    order by fm.display_name, ci.creature_name, ci.acquired_at;
  end;
  $$;

  create or replace function public.admin_remove_family_creature(p_family_id uuid, p_creature_instance_id uuid)
  returns void
  language plpgsql
  security definer
  set search_path = public, pg_temp
  as $$
  declare
    v_creature public.creature_inventory%rowtype;
    v_member public.family_members%rowtype;
  begin
    if auth.uid() is null or not public.app_is_family_admin(p_family_id) then
      raise exception 'Only a family admin can manage creature collections';
    end if;

    select * into v_creature
    from public.creature_inventory
    where id=p_creature_instance_id and family_id=p_family_id
    for update;
    if not found or v_creature.removed_at is not null then
      raise exception 'Creature was not found in this family collection';
    end if;
    select * into v_member from public.family_members
    where family_id=p_family_id and user_id=v_creature.user_id and is_active
    for update;
    if not found then raise exception 'Creature owner is no longer an active family member'; end if;

    update public.creature_ability_requests
    set status='rejected', decided_by=auth.uid(), decided_at=now(),
        decision_reason='Varelsen har tagits bort från samlingen.'
    where creature_instance_id=v_creature.id and family_id=p_family_id and status='pending';

    delete from public.creature_effects
    where family_id=p_family_id and user_id=v_creature.user_id and creature_id=v_creature.id;

    update public.creature_inventory
    set removed_at=now(), removed_by=auth.uid()
    where id=v_creature.id and family_id=p_family_id and removed_at is null;

    insert into public.notifications(family_id,user_id,message)
    values(p_family_id,v_creature.user_id,'En administratör tog bort '||v_creature.creature_name||' från din varelsesamling.');
  end;
  $$;

  revoke all on function public.admin_list_family_creatures(uuid) from public, anon;
  revoke all on function public.admin_remove_family_creature(uuid, uuid) from public, anon;
  grant execute on function public.admin_list_family_creatures(uuid) to authenticated;
  grant execute on function public.admin_remove_family_creature(uuid, uuid) to authenticated;

  notify pgrst, 'reload schema';
