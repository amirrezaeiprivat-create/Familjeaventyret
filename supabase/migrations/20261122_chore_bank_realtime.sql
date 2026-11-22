-- Keep the shared bonus-task list current for family members already in the app.
do $$
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime')
     and not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename='chore_bank_items') then
    alter publication supabase_realtime add table public.chore_bank_items;
  end if;
end;
$$;
