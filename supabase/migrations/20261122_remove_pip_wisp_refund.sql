-- Remove Pip and Wisp from future drops and current collections.
-- Refund 35 tokens only when the currently held creature matches a paid wooden
-- chest opening. The refund ledger makes this safe to rerun.

create table if not exists public.creature_removal_refunds (
  inventory_id uuid primary key,
  family_id uuid not null,
  user_id uuid not null,
  creature_name text not null,
  token_amount integer not null check (token_amount > 0),
  chest_opening_id uuid not null,
  refunded_at timestamptz not null default now()
);

alter table public.creature_removal_refunds enable row level security;
revoke all on public.creature_removal_refunds from public, anon, authenticated;

with eligible as (
  select ci.id as inventory_id, ci.family_id, ci.user_id, ci.creature_name,
         co.id as chest_opening_id
  from public.creature_inventory ci
  join public.creature_chest_openings co
    on co.family_id = ci.family_id
   and co.user_id = ci.user_id
   and co.created_at = ci.acquired_at
   and co.chest_type = 'wooden'
   and co.result->>'creature_id' = ci.creature_id
   and co.result->>'free_chest' = 'false'
  where lower(ci.creature_id) in ('pip', 'wisp')
    and ci.consumed_at is null
    and ci.removed_at is null
), refunded as (
  insert into public.creature_removal_refunds
    (inventory_id, family_id, user_id, creature_name, token_amount, chest_opening_id)
  select inventory_id, family_id, user_id, creature_name, 35, chest_opening_id
  from eligible
  on conflict (inventory_id) do nothing
  returning family_id, user_id, creature_name, token_amount
), balances as (
  select family_id, user_id, sum(token_amount)::integer as amount,
         string_agg(creature_name, ', ' order by creature_name) as creatures
  from refunded
  group by family_id, user_id
), credited as (
  update public.family_members fm
  set tokens = fm.tokens + balances.amount
  from balances
  where fm.family_id = balances.family_id
    and fm.user_id = balances.user_id
  returning fm.family_id, fm.user_id, balances.amount, balances.creatures
)
insert into public.notifications (family_id, user_id, message)
select family_id, user_id,
       creatures || ' har tagits bort. ' || amount || ' mynt för träkistan har återbetalats.'
from credited;

update public.creature_inventory
set removed_at = coalesce(removed_at, now())
where lower(creature_id) in ('pip', 'wisp')
  and consumed_at is null
  and removed_at is null;

update public.creature_catalog
set wooden_weight = 0, silver_weight = 0, gold_weight = 0, diamond_weight = 0
where creature_id in ('pip', 'wisp');

delete from public.creature_ability_catalog
where creature_id in ('pip', 'wisp');

