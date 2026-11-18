-- Server-owned creature inventory and active ability effects.
create table if not exists public.creature_inventory (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  creature_id text not null,
  creature_name text not null,
  rarity text not null check (rarity in ('Common','Uncommon','Rare','Epic','Legendary','Curse')),
  level integer not null default 1 check (level between 1 and 5),
  creature_xp integer not null default 0 check (creature_xp >= 0),
  is_cursed boolean not null default false,
  cooldown_until timestamptz,
  acquired_at timestamptz not null default now()
);
create index if not exists creature_inventory_owner_idx on public.creature_inventory(family_id,user_id);

create table if not exists public.creature_effects (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  creature_id uuid references public.creature_inventory(id) on delete cascade,
  effect_key text not null,
  payload jsonb not null default '{}'::jsonb,
  uses_remaining integer not null default 1 check (uses_remaining >= 0),
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists creature_effects_active_idx on public.creature_effects(family_id,user_id,effect_key,expires_at);

alter table public.creature_inventory enable row level security;
alter table public.creature_effects enable row level security;
drop policy if exists creature_inventory_read_family on public.creature_inventory;
create policy creature_inventory_read_family on public.creature_inventory for select to authenticated
  using (user_id=auth.uid() and public.app_is_family_member(family_id));
drop policy if exists creature_effects_read_self on public.creature_effects;
create policy creature_effects_read_self on public.creature_effects for select to authenticated
  using (user_id=auth.uid() and public.app_is_family_member(family_id));
revoke all on public.creature_inventory,public.creature_effects from anon,authenticated;
grant select on public.creature_inventory,public.creature_effects to authenticated;
notify pgrst, 'reload schema';
