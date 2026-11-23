-- Keep bonus chores in the bank and let a configurable number of distinct
-- family members reserve each listing before one shared weekly chore is made.
alter table public.chore_bank_items
  add column required_people integer not null default 1 check (required_people between 1 and 20),
  add column cooldown_days integer not null default 7 check (cooldown_days between 0 and 365),
  add column cooldown_until timestamptz,
  add column active_cycle_id uuid;

-- Existing claim metadata remains intact for history; the new reusable flow
-- uses cooldown_until and active reservations instead of claimed_* fields.

create table public.chore_bank_reservations (
  family_id uuid not null references public.families(id) on delete cascade,
  item_id uuid not null references public.chore_bank_items(id) on delete cascade,
  cycle_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  reserved_at timestamptz not null default now(),
  primary key (item_id, user_id)
);

create index chore_bank_reservations_family_idx
  on public.chore_bank_reservations (family_id, item_id, reserved_at);

alter table public.chore_bank_reservations enable row level security;
create policy chore_bank_reservations_read_family
  on public.chore_bank_reservations for select to authenticated
  using (public.app_is_family_member(family_id));
revoke all on public.chore_bank_reservations from anon, authenticated;
grant select on public.chore_bank_reservations to authenticated;

do $$
begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='chore_bank_reservations') then
    alter publication supabase_realtime add table public.chore_bank_reservations;
  end if;
end;
$$;

create or replace function public.admin_create_chore_bank_item_configured(
  p_family_id uuid,
  p_title text,
  p_description text,
  p_xp integer,
  p_tokens integer,
  p_difficulty text,
  p_required_people integer,
  p_cooldown_days integer
)
returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid; v_active_members integer;
begin
  if auth.uid() is null or not public.app_is_family_admin(p_family_id) then
    raise exception 'Endast familjens administratörer får lägga till extrasysslor.';
  end if;
  if length(trim(coalesce(p_title,''))) not between 1 and 85 then raise exception 'Ange ett namn med 1 till 85 tecken.'; end if;
  if length(coalesce(p_description,'')) > 300 then raise exception 'Beskrivningen får vara högst 300 tecken.'; end if;
  if p_difficulty not in ('Lätt','Mellan','Svår') then raise exception 'Ogiltig svårighetsgrad.'; end if;
  if p_xp is null or p_xp not between 0 and 500 or p_tokens is null or p_tokens not between 0 and 100 then raise exception 'XP eller mynt ligger utanför tillåtna värden.'; end if;
  if p_required_people is null or p_required_people not between 1 and 20 then raise exception 'Välj mellan 1 och 20 personer.'; end if;
  if p_cooldown_days is null or p_cooldown_days not between 0 and 365 then raise exception 'Viloperioden ska vara mellan 0 och 365 dagar.'; end if;
  select count(*) into v_active_members from public.family_members where family_id=p_family_id and is_active;
  if p_required_people > v_active_members then raise exception 'Det behövs fler aktiva familjemedlemmar för så många platser.'; end if;
  insert into public.chore_bank_items(family_id,title,description,difficulty,xp_reward,token_reward,created_by,required_people,cooldown_days)
  values(p_family_id,trim(p_title),trim(coalesce(p_description,'')),p_difficulty,p_xp,p_tokens,auth.uid(),p_required_people,p_cooldown_days)
  returning id into v_id;
  return v_id;
end;
$$;

-- Preserve compatibility with already cached clients using the original RPC.
create or replace function public.admin_create_chore_bank_item(
  p_family_id uuid, p_title text, p_description text, p_xp integer, p_tokens integer, p_difficulty text
)
returns uuid
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.admin_create_chore_bank_item_configured(p_family_id,p_title,p_description,p_xp,p_tokens,p_difficulty,1,7);
$$;

create or replace function public.admin_update_chore_bank_item(
  p_item_id uuid,
  p_title text,
  p_description text,
  p_xp integer,
  p_tokens integer,
  p_difficulty text,
  p_required_people integer,
  p_cooldown_days integer
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_item public.chore_bank_items%rowtype; v_active_members integer; v_reserved integer;
begin
  select * into v_item from public.chore_bank_items where id=p_item_id for update;
  if not found or auth.uid() is null or not public.app_is_family_admin(v_item.family_id) then raise exception 'Sysselbanksuppgiften hittades inte eller så saknas administratörsbehörighet.'; end if;
  if length(trim(coalesce(p_title,''))) not between 1 and 85 then raise exception 'Ange ett namn med 1 till 85 tecken.'; end if;
  if length(coalesce(p_description,'')) > 300 then raise exception 'Beskrivningen får vara högst 300 tecken.'; end if;
  if p_difficulty not in ('Lätt','Mellan','Svår') then raise exception 'Ogiltig svårighetsgrad.'; end if;
  if p_xp is null or p_xp not between 0 and 500 or p_tokens is null or p_tokens not between 0 and 100 then raise exception 'XP eller mynt ligger utanför tillåtna värden.'; end if;
  if p_required_people is null or p_required_people not between 1 and 20 then raise exception 'Välj mellan 1 och 20 personer.'; end if;
  if p_cooldown_days is null or p_cooldown_days not between 0 and 365 then raise exception 'Viloperioden ska vara mellan 0 och 365 dagar.'; end if;
  select count(*) into v_active_members from public.family_members where family_id=v_item.family_id and is_active;
  select count(*) into v_reserved from public.chore_bank_reservations where item_id=p_item_id;
  if p_required_people > v_active_members then raise exception 'Det behövs fler aktiva familjemedlemmar för så många platser.'; end if;
  if v_reserved > 0 and p_required_people <= v_reserved then raise exception 'Vänta tills reservationerna är fulla innan du sänker antalet personer.'; end if;
  update public.chore_bank_items set title=trim(p_title),description=trim(coalesce(p_description,'')),xp_reward=p_xp,token_reward=p_tokens,difficulty=p_difficulty,required_people=p_required_people,cooldown_days=p_cooldown_days where id=p_item_id;
end;
$$;

create or replace function public.admin_delete_chore_bank_item(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_family_id uuid;
begin
  select family_id into v_family_id from public.chore_bank_items where id=p_item_id for update;
  if not found or auth.uid() is null or not public.app_is_family_admin(v_family_id) then raise exception 'Sysselbanksuppgiften hittades inte eller så saknas administratörsbehörighet.'; end if;
  delete from public.chore_bank_items where id=p_item_id;
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
  v_cycle_id uuid;
  v_reserved integer;
  v_today_week date := date_trunc('week', now() at time zone 'Europe/Stockholm')::date;
begin
  if auth.uid() is null then raise exception 'Logga in för att reservera en extrasyssla.'; end if;
  select * into v_item from public.chore_bank_items where id=p_item_id for update;
  if not found or not v_item.is_active then raise exception 'Sysselbanksuppgiften finns inte längre.'; end if;
  if not public.app_is_family_member(v_item.family_id) then raise exception 'Du är inte medlem i den här familjen.'; end if;
  if v_item.cooldown_until is not null and v_item.cooldown_until > now() then raise exception 'Sysslan vilar fortfarande.'; end if;
  if exists(select 1 from public.chores where family_id=v_item.family_id and kind='curse' and resolved_at is null) then raise exception 'Resolve active curses first'; end if;
  select * into v_plan from public.weekly_plans where family_id=v_item.family_id and week_start=v_today_week and status='open' for update;
  if not found then raise exception 'Ingen öppen veckoplan hittades.'; end if;

  -- A member who left the family must not hold a reservation slot forever.
  delete from public.chore_bank_reservations r
  where r.item_id=p_item_id and not exists(
    select 1 from public.family_members m where m.family_id=r.family_id and m.user_id=r.user_id and m.is_active
  );
  if exists(select 1 from public.chore_bank_reservations where item_id=p_item_id and user_id=auth.uid()) then raise exception 'Du har redan reserverat en plats för den här sysslan.'; end if;
  select count(*) into v_reserved from public.chore_bank_reservations where item_id=p_item_id;
  if v_reserved >= v_item.required_people then raise exception 'Alla platser är redan reserverade.'; end if;
  v_cycle_id := coalesce(v_item.active_cycle_id,gen_random_uuid());
  insert into public.chore_bank_reservations(family_id,item_id,cycle_id,user_id)
  values(v_item.family_id,p_item_id,v_cycle_id,auth.uid());
  update public.chore_bank_items set active_cycle_id=v_cycle_id where id=p_item_id;
  v_reserved := v_reserved + 1;
  if v_reserved < v_item.required_people then return null; end if;

  insert into public.chores(family_id,plan_id,kind,title,description,difficulty,xp_reward,token_reward,created_by)
  values(v_item.family_id,v_plan.id,'weekly',v_item.title,v_item.description,v_item.difficulty,v_item.xp_reward,v_item.token_reward,auth.uid())
  returning id into v_chore_id;
  insert into public.chore_assignments(family_id,chore_id,user_id,assigned_by)
  select v_item.family_id,v_chore_id,r.user_id,auth.uid()
  from public.chore_bank_reservations r
  join public.family_members m on m.family_id=r.family_id and m.user_id=r.user_id and m.is_active
  where r.item_id=p_item_id and r.cycle_id=v_cycle_id;
  delete from public.chore_bank_reservations where item_id=p_item_id and cycle_id=v_cycle_id;
  update public.chore_bank_items
  set active_cycle_id=null,
      cooldown_until=case when cooldown_days=0 then null else now()+make_interval(days=>cooldown_days) end,
      claimed_by=null,claimed_at=null,claimed_chore_id=null
  where id=p_item_id;
  return v_chore_id;
end;
$$;

revoke all on function public.admin_create_chore_bank_item_configured(uuid,text,text,integer,integer,text,integer,integer) from public,anon;
grant execute on function public.admin_create_chore_bank_item_configured(uuid,text,text,integer,integer,text,integer,integer) to authenticated;
revoke all on function public.admin_create_chore_bank_item(uuid,text,text,integer,integer,text) from public,anon;
grant execute on function public.admin_create_chore_bank_item(uuid,text,text,integer,integer,text) to authenticated;
revoke all on function public.admin_update_chore_bank_item(uuid,text,text,integer,integer,text,integer,integer) from public,anon;
grant execute on function public.admin_update_chore_bank_item(uuid,text,text,integer,integer,text,integer,integer) to authenticated;
revoke all on function public.admin_delete_chore_bank_item(uuid) from public,anon;
grant execute on function public.admin_delete_chore_bank_item(uuid) to authenticated;
revoke all on function public.claim_chore_bank_item(uuid) from public,anon;
grant execute on function public.claim_chore_bank_item(uuid) to authenticated;

notify pgrst, 'reload schema';
