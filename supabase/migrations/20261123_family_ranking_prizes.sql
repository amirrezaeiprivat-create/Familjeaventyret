create table if not exists public.family_ranking_prizes (
  family_id uuid primary key references public.families(id) on delete cascade,
  day_prize text not null default '' check (char_length(day_prize) <= 160),
  week_prize text not null default '' check (char_length(week_prize) <= 160),
  season_prize text not null default '' check (char_length(season_prize) <= 160),
  updated_at timestamptz not null default now()
);

alter table public.family_ranking_prizes enable row level security;
revoke all on public.family_ranking_prizes from anon, authenticated;
grant select, insert, update on public.family_ranking_prizes to authenticated;

drop policy if exists family_ranking_prizes_read on public.family_ranking_prizes;
create policy family_ranking_prizes_read
  on public.family_ranking_prizes for select to authenticated
  using (public.app_is_family_member(family_id));

drop policy if exists family_ranking_prizes_insert on public.family_ranking_prizes;
create policy family_ranking_prizes_insert
  on public.family_ranking_prizes for insert to authenticated
  with check (public.app_is_family_admin(family_id));

drop policy if exists family_ranking_prizes_update on public.family_ranking_prizes;
create policy family_ranking_prizes_update
  on public.family_ranking_prizes for update to authenticated
  using (public.app_is_family_admin(family_id))
  with check (public.app_is_family_admin(family_id));
