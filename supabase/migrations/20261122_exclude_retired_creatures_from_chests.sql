-- Keep the old catalog entries for audit/history, but ensure new chest rolls
-- cannot select Pip or Wisp and preserve the intended rarity weights.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.open_creature_chest(uuid,text,uuid,uuid)'::regprocedure)
    into v_definition;
  v_definition := replace(
    v_definition,
    'where not c.is_cursed order by',
    'where not c.is_cursed and c.creature_id not in (''pip'',''wisp'') order by'
  );
  v_definition := replace(v_definition, '50.0/15', '50.0/14');
  v_definition := replace(v_definition, '25.0/12', '25.0/11');
  if position('c.creature_id not in (''pip'',''wisp'')' in v_definition) = 0
     or position('50.0/14' in v_definition) = 0
     or position('25.0/11' in v_definition) = 0 then
    raise exception 'Could not update retired creature chest selection';
  end if;
  execute v_definition;
end $$;

notify pgrst, 'reload schema';

