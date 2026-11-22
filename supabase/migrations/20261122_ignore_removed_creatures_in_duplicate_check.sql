-- A consumed or admin-removed creature must not count as a duplicate.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.open_creature_chest(uuid,text,uuid,uuid)'::regprocedure)
    into v_definition;
  v_definition := replace(
    v_definition,
    'and creature_id=v_pick.creature_id and not is_cursed) into v_dup',
    'and creature_id=v_pick.creature_id and not is_cursed and consumed_at is null and removed_at is null) into v_dup'
  );
  if position('consumed_at is null and removed_at is null) into v_dup' in v_definition) = 0 then
    raise exception 'Could not update creature duplicate check';
  end if;
  execute v_definition;
end $$;

-- Repair any already logged duplicate result caused solely by an earlier
-- consumed/removed instance. Restore the intended creature and reverse the
-- duplicate shards, while preserving any independent chest bonus shards.
with incorrect as (
  select co.id as opening_id, co.family_id, co.user_id, co.created_at,
         co.result, co.result->>'creature_id' as creature_id,
         co.result->>'creature_name' as creature_name,
         co.result->>'rarity' as rarity,
         case co.result->>'rarity'
           when 'Common' then 5 when 'Uncommon' then 10 when 'Rare' then 20
           when 'Epic' then 35 else 50
         end as duplicate_shards
  from public.creature_chest_openings co
  where co.result->>'is_duplicate' = 'true'
    and exists (
      select 1 from public.creature_inventory old
      where old.family_id=co.family_id and old.user_id=co.user_id
        and old.creature_id=co.result->>'creature_id'
        and ((old.removed_at is not null and old.removed_at<=co.created_at)
          or (old.consumed_at is not null and old.consumed_at<=co.created_at))
    )
    and not exists (
      select 1 from public.creature_inventory active
      where active.family_id=co.family_id and active.user_id=co.user_id
        and active.creature_id=co.result->>'creature_id'
        and active.acquired_at<=co.created_at
        and (active.removed_at is null or active.removed_at>co.created_at)
        and (active.consumed_at is null or active.consumed_at>co.created_at)
    )
), adjusted as (
  update public.family_members fm
  set shards=greatest(0,fm.shards-i.duplicate_shards)
  from incorrect i
  where fm.family_id=i.family_id and fm.user_id=i.user_id
  returning fm.family_id,fm.user_id
), added as (
  insert into public.creature_inventory(family_id,user_id,creature_id,creature_name,rarity)
  select i.family_id,i.user_id,i.creature_id,i.creature_name,i.rarity
  from incorrect i
  join adjusted a on a.family_id=i.family_id and a.user_id=i.user_id
  returning family_id,user_id,creature_id
), corrected as (
  update public.creature_chest_openings co
  set result=jsonb_set(
    jsonb_set(
      jsonb_set(co.result,'{is_duplicate}','false'::jsonb),
      '{shards_awarded}',to_jsonb(coalesce((co.result->>'bonus_shards_awarded')::integer,0))
    ),
    '{shards}',to_jsonb(greatest(0,(co.result->>'shards')::integer-i.duplicate_shards))
  )
  from incorrect i
  where co.id=i.opening_id
    and exists(select 1 from added a where a.family_id=i.family_id and a.user_id=i.user_id and a.creature_id=i.creature_id)
  returning co.family_id,co.user_id,co.result->>'creature_name' as creature_name
)
insert into public.notifications(family_id,user_id,message)
select family_id,user_id,
       'Kistöppningen har rättats: '||creature_name||' finns nu i din samling i stället för att räknas som en dubblett.'
from corrected;

notify pgrst, 'reload schema';

