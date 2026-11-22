-- Retire shards as a currency. Convert any saved balances 1:1 into coins,
-- then award duplicate and chest bonus rewards as tokens.
update public.family_members
set tokens=tokens+shards, shards=0
where shards>0;

update public.creature_ability_catalog
set effect_key=case creature_id
      when 'chestnut' then 'bonus_tokens_next_chest'
      when 'prism' then 'bonus_duplicate_tokens'
      when 'voidstar' then 'free_chest_tokens'
      else effect_key
    end,
    config=case when config ? 'shards'
      then (config-'shards') || jsonb_build_object('tokens',config->'shards')
      else config end
where creature_id in ('chestnut','prism','celestia','voidstar');

update public.creature_effects
set effect_key=case effect_key
      when 'bonus_shards_next_chest' then 'bonus_tokens_next_chest'
      when 'bonus_duplicate_shards' then 'bonus_duplicate_tokens'
      else effect_key
    end,
    payload=case when payload ? 'shards'
      then (payload-'shards') || jsonb_build_object('tokens',payload->'shards')
      else payload end
where effect_key in ('bonus_shards_next_chest','bonus_duplicate_shards','bonus_next_chest')
   or payload ? 'shards';

do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.open_creature_chest(uuid,text,uuid,uuid)'::regprocedure)
    into v_definition;
  v_definition:=replace(v_definition,
    'update public.family_members set shards=shards+v_shards',
    'update public.family_members set tokens=tokens+v_shards');
  v_definition:=replace(v_definition, '''shards_awarded''', '''tokens_awarded''');
  v_definition:=replace(v_definition, '''bonus_shards_awarded''', '''bonus_tokens_awarded''');
  v_definition:=replace(v_definition, '''bonus_shards_next_chest''', '''bonus_tokens_next_chest''');
  v_definition:=replace(v_definition, '''bonus_duplicate_shards''', '''bonus_duplicate_tokens''');
  v_definition:=replace(v_definition, '->>''shards''', '->>''tokens''');
  v_definition:=replace(v_definition, ',''shards'',m.shards', '');
  if position('set tokens=tokens+v_shards' in v_definition)=0
     or position('''tokens_awarded''' in v_definition)=0
     or position('''shards_awarded''' in v_definition)>0
     or position('''shards'',m.shards' in v_definition)>0 then
    raise exception 'Could not convert chest duplicate rewards to coins';
  end if;
  execute v_definition;
end $$;

do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.use_creature_ability(uuid,uuid,uuid,uuid,uuid,uuid,uuid)'::regprocedure)
    into v_definition;
  v_definition:=replace(v_definition, '''free_chest_shards''', '''free_chest_tokens''');
  v_definition:=replace(v_definition,
    'jsonb_build_object(''shards'',coalesce((v_rule.config->>''shards'')::integer,5))',
    'jsonb_build_object(''tokens'',coalesce((v_rule.config->>''tokens'')::integer,5))');
  if position('''free_chest_shards''' in v_definition)>0
     or position('''tokens'',coalesce((v_rule.config->>''tokens'')::integer,5)' in v_definition)=0 then
    raise exception 'Could not convert creature chest bonuses to coins';
  end if;
  execute v_definition;
end $$;

notify pgrst, 'reload schema';

