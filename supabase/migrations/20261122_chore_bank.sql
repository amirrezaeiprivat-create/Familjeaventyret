-- Admins publish one-time bonus chores; a family member claims each offer once.
create table if not exists public.chore_bank_items (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  title text not null check (length(trim(title)) between 1 and 85),
  description text not null default '' check (length(description) <= 300),
  difficulty text not null default 'Lätt' check (difficulty in ('Lätt','Mellan','Svår')),
  xp_reward integer not null default 15 check (xp_reward between 0 and 500),
  token_reward integer not null default 3 check (token_reward between 0 and 100),
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  claimed_by uuid references auth.users(id),
  claimed_at timestamptz,
  claimed_chore_id uuid references public.chores(id),
  constraint chore_bank_claim_consistency check (
    (claimed_at is null and claimed_by is null and claimed_chore_id is null)
    or (claimed_at is not null and claimed_by is not null and claimed_chore_id is not null)
  )
);

create index if not exists chore_bank_items_family_available_idx
  on public.chore_bank_items (family_id, created_at desc)
  where is_active and claimed_at is null;

alter table public.chore_bank_items enable row level security;
drop policy if exists chore_bank_items_read_family on public.chore_bank_items;
create policy chore_bank_items_read_family on public.chore_bank_items
  for select to authenticated
  using (public.app_is_family_member(family_id));

revoke all on public.chore_bank_items from anon, authenticated;
grant select on public.chore_bank_items to authenticated;

create or replace function public.admin_create_chore_bank_item(
  p_family_id uuid,
  p_title text,
  p_description text,
  p_xp integer,
  p_tokens integer,
  p_difficulty text
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  if auth.uid() is null or not public.app_is_family_admin(p_family_id) then
    raise exception 'Endast familjens administratörer får lägga till extrasysslor.';
  end if;
  if length(trim(coalesce(p_title,''))) not between 1 and 85 then
    raise exception 'Ange ett namn med 1 till 85 tecken.';
  end if;
  if length(coalesce(p_description,'')) > 300 then raise exception 'Beskrivningen får vara högst 300 tecken.'; end if;
  if p_difficulty not in ('Lätt','Mellan','Svår') then raise exception 'Ogiltig svårighetsgrad.'; end if;
  if p_xp is null or p_xp not between 0 and 500 or p_tokens is null or p_tokens not between 0 and 100 then
    raise exception 'XP eller mynt ligger utanför tillåtna värden.';
  end if;
  insert into public.chore_bank_items(family_id,title,description,difficulty,xp_reward,token_reward,created_by)
  values(p_family_id,trim(p_title),trim(coalesce(p_description,'')),p_difficulty,p_xp,p_tokens,auth.uid())
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.claim_chore_bank_item(p_item_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_item public.chore_bank_items%rowtype;
  v_plan public.weekly_plans%rowtype;
  v_chore_id uuid;
  v_today_week date := date_trunc('week', now() at time zone 'Europe/Stockholm')::date;
begin
  if auth.uid() is null then raise exception 'Logga in för att ta en extrasyssla.'; end if;
  select * into v_item from public.chore_bank_items where id=p_item_id for update;
  if not found or not v_item.is_active or v_item.claimed_at is not null then
    raise exception 'Extrasysslan är inte längre ledig.';
  end if;
  if not public.app_is_family_member(v_item.family_id) then raise exception 'Du är inte medlem i den här familjen.'; end if;
  if exists(select 1 from public.chores where family_id=v_item.family_id and kind='curse' and resolved_at is null) then
    raise exception 'Resolve active curses first';
  end if;
  select * into v_plan from public.weekly_plans
  where family_id=v_item.family_id and week_start=v_today_week and status='open'
  for update;
  if not found then raise exception 'Ingen öppen veckoplan hittades.'; end if;

  insert into public.chores(family_id,plan_id,kind,title,description,difficulty,xp_reward,token_reward,created_by)
  values(v_item.family_id,v_plan.id,'weekly',v_item.title,v_item.description,v_item.difficulty,v_item.xp_reward,v_item.token_reward,auth.uid())
  returning id into v_chore_id;
  insert into public.chore_assignments(family_id,chore_id,user_id,assigned_by)
  values(v_item.family_id,v_chore_id,auth.uid(),auth.uid());
  update public.chore_bank_items
  set claimed_by=auth.uid(),claimed_at=now(),claimed_chore_id=v_chore_id
  where id=v_item.id;
  return v_chore_id;
end;
$$;

revoke all on function public.admin_create_chore_bank_item(uuid,text,text,integer,integer,text) from public, anon;
grant execute on function public.admin_create_chore_bank_item(uuid,text,text,integer,integer,text) to authenticated;
revoke all on function public.claim_chore_bank_item(uuid) from public, anon;
grant execute on function public.claim_chore_bank_item(uuid) to authenticated;

notify pgrst, 'reload schema';
