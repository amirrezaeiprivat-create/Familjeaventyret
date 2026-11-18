-- Link each cursed creature to the curse chore that it created, then remove it atomically when the chore is approved.
alter table public.creature_inventory
  add column if not exists curse_chore_id uuid references public.chores(id) on delete cascade;

create index if not exists creature_inventory_curse_chore_idx
  on public.creature_inventory(curse_chore_id) where curse_chore_id is not null;

create or replace function public.link_curse_creature_to_chore()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if new.kind = 'curse' then
    update public.creature_inventory
       set curse_chore_id = new.id
     where id = (
       select ci.id from public.creature_inventory ci
        where ci.family_id = new.family_id
          and ci.user_id = new.created_by
          and ci.creature_name = new.title
          and ci.is_cursed
          and ci.curse_chore_id is null
        order by ci.acquired_at desc
        limit 1
        for update
     );
  end if;
  return new;
end;
$$;

drop trigger if exists link_curse_creature_to_chore on public.chores;
create trigger link_curse_creature_to_chore
after insert on public.chores
for each row execute function public.link_curse_creature_to_chore();

create or replace function public.remove_curse_creature_after_chore_approval()
returns trigger language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if new.kind = 'curse' and old.resolved_at is null and new.resolved_at is not null then
    delete from public.creature_inventory where curse_chore_id = new.id;
    if not found then
      delete from public.creature_inventory
       where id = (
         select ci.id from public.creature_inventory ci
          where ci.family_id = new.family_id
            and ci.user_id = new.created_by
            and ci.creature_name = new.title
            and ci.is_cursed
          order by ci.acquired_at desc
          limit 1
          for update
       );
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists remove_curse_creature_after_chore_approval on public.chores;
create trigger remove_curse_creature_after_chore_approval
after update of resolved_at on public.chores
for each row execute function public.remove_curse_creature_after_chore_approval();

revoke all on function public.link_curse_creature_to_chore() from public,anon,authenticated;
revoke all on function public.remove_curse_creature_after_chore_approval() from public,anon,authenticated;
notify pgrst, 'reload schema';
