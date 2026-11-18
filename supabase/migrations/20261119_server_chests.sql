-- Server-side chest purchases, weighted drops, duplicate shards, and curse creation.
create table if not exists public.creature_catalog (
  creature_id text primary key,
  creature_name text not null unique,
  rarity text not null check (rarity in ('Common','Uncommon','Rare','Epic','Legendary','Curse')),
  is_cursed boolean not null default false,
  curse_task text,
  deadline_hours integer,
  wooden_weight numeric not null default 0,
  silver_weight numeric not null default 0,
  gold_weight numeric not null default 0,
  diamond_weight numeric not null default 0,
  steals_tokens integer not null default 0
);

insert into public.creature_catalog(creature_id,creature_name,rarity) values
('dusty','Dusty','Common'),('puddle','Puddle','Common'),('nibble','Nibble','Common'),('pip','Pip','Common'),('shelly','Shelly','Common'),('bristle','Bristle','Common'),('acorn','Acorn','Common'),('misty','Misty','Common'),('pebble','Pebble','Common'),('echo','Echo','Common'),('cloudy','Cloudy','Common'),('flutter','Flutter','Common'),('mossy','Mossy','Common'),('clack','Clack','Common'),('tumble','Tumble','Common'),
('flicker','Flicker','Uncommon'),('bandit','Bandit','Uncommon'),('wisp','Wisp','Uncommon'),('fern','Fern','Uncommon'),('buzz','Buzz','Uncommon'),('howler','Howler','Uncommon'),('ripple','Ripple','Uncommon'),('glimmer','Glimmer','Uncommon'),('chestnut','Chestnut','Uncommon'),('jolly','Jolly','Uncommon'),('pebblehorn','Pebblehorn','Uncommon'),('slink','Slink','Uncommon'),
('ember','Ember','Rare'),('skyrush','Skyrush','Rare'),('moonhart','Moonhart','Rare'),('boulder','Boulder','Rare'),('marina','Marina','Rare'),('shadowpaw','Shadowpaw','Rare'),('crystalwing','Crystalwing','Rare'),('tideback','Tideback','Rare'),('venom','Venom','Rare'),('frosthorn','Frosthorn','Rare'),
('inferno','Inferno','Epic'),('lunara','Lunara','Epic'),('volt','Volt','Epic'),('elderroot','Elderroot','Epic'),('glacius','Glacius','Epic'),('prism','Prism','Epic'),('dreamweaver','Dreamweaver','Epic'),('tricksy','Tricksy','Epic'),
('aureon','Aureon','Legendary'),('solstice','Solstice','Legendary'),('titan','Titan','Legendary'),('celestia','Celestia','Legendary'),('voidstar','Voidstar','Legendary')
on conflict (creature_id) do update set creature_name=excluded.creature_name,rarity=excluded.rarity,is_cursed=false;

insert into public.creature_catalog(creature_id,creature_name,rarity,is_cursed,curse_task,deadline_hours,wooden_weight,silver_weight,gold_weight,diamond_weight,steals_tokens) values
('grumble','Grumble','Curse',true,'Torka av köksbordet.',24,1.9,.9,.3,.1,0),
('snatcher','Snatcher','Curse',true,'Plocka undan skor och jackor i hallen.',24,1.9,.9,.3,.1,5),
('snoozer','Snoozer','Curse',true,'Sortera och organisera en mindre del av ett rum.',24,1.9,.9,.3,.1,0),
('thorn','Thorn','Curse',true,'Dammsug under soffan.',48,1.9,.9,.3,.1,0),
('blazebit','Blazebit','Curse',true,'Plocka undan i vardagsrummet och vattna en växt.',48,1.9,.9,.3,.1,0),
('dreadlord','Dreadlord','Curse',true,'Rengör hela badrummet grundligt.',72,.5,.5,.5,.5,0)
on conflict (creature_id) do update set creature_name=excluded.creature_name,rarity=excluded.rarity,is_cursed=true,curse_task=excluded.curse_task,deadline_hours=excluded.deadline_hours,wooden_weight=excluded.wooden_weight,silver_weight=excluded.silver_weight,gold_weight=excluded.gold_weight,diamond_weight=excluded.diamond_weight,steals_tokens=excluded.steals_tokens;

create table if not exists public.creature_chest_openings (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  request_key uuid not null,
  chest_type text not null check(chest_type in ('wooden','silver','gold','diamond')),
  result jsonb,
  created_at timestamptz not null default now(),
  unique(user_id,request_key)
);
alter table public.creature_catalog enable row level security;
alter table public.creature_chest_openings enable row level security;
revoke all on public.creature_catalog,public.creature_chest_openings from public,anon,authenticated;

create or replace function public.open_creature_chest(p_family_id uuid,p_chest_type text,p_request_key uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_member public.family_members%rowtype; v_cost integer; v_chance numeric; v_pick public.creature_catalog%rowtype; v_existing jsonb; v_dup boolean:=false; v_shards integer:=0; v_chore uuid; v_opening uuid; v_inserted integer; v_active_curses integer;
begin
  if auth.uid() is null then raise exception 'Sign in is required'; end if;
  if p_request_key is null then raise exception 'An idempotency key is required'; end if;
  if p_chest_type is null or p_chest_type not in ('wooden','silver','gold','diamond') then raise exception 'Unknown chest type'; end if;
  v_cost:=case p_chest_type when 'wooden' then 35 when 'silver' then 70 when 'gold' then 110 else 160 end;
  select * into v_member from public.family_members where family_id=p_family_id and user_id=auth.uid() and is_active for update;
  if not found then raise exception 'Active family membership required'; end if;
  select result into v_existing from public.creature_chest_openings where user_id=auth.uid() and request_key=p_request_key;
  if found then
    if v_existing is null then raise exception 'Chest opening is already processing'; end if;
    return v_existing;
  end if;
  insert into public.creature_chest_openings(family_id,user_id,request_key,chest_type) values(p_family_id,auth.uid(),p_request_key,p_chest_type) on conflict(user_id,request_key) do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then select result into v_existing from public.creature_chest_openings where user_id=auth.uid() and request_key=p_request_key; if v_existing is null then raise exception 'Chest opening is already processing'; end if; return v_existing; end if;
  select id into v_opening from public.creature_chest_openings where user_id=auth.uid() and request_key=p_request_key;
  update public.creature_chest_openings set family_id=v_member.family_id where id=v_opening;
  if v_member.tokens<v_cost then raise exception 'Not enough coins for this chest'; end if;
  update public.family_members set tokens=tokens-v_cost where family_id=v_member.family_id and user_id=auth.uid();
  v_chance:=case p_chest_type when 'wooden' then 10 when 'silver' then 5 when 'gold' then 2 else 1 end;
  select count(*) into v_active_curses from public.chores where family_id=v_member.family_id and kind='curse' and resolved_at is null and is_active;
  if v_active_curses<3 and random()*100<v_chance then
    select c.* into v_pick from public.creature_catalog c where c.is_cursed and (case p_chest_type when 'wooden' then c.wooden_weight when 'silver' then c.silver_weight when 'gold' then c.gold_weight else c.diamond_weight end)>0 order by -ln(greatest(random(),0.000000001))/(case p_chest_type when 'wooden' then c.wooden_weight when 'silver' then c.silver_weight when 'gold' then c.gold_weight else c.diamond_weight end) limit 1;
  else
    select c.* into v_pick from public.creature_catalog c where not c.is_cursed order by -ln(greatest(random(),0.000000001))/(case c.rarity when 'Common' then 50.0/15 when 'Uncommon' then 25.0/12 when 'Rare' then 15.0/10 when 'Epic' then 8.0/8 else 2.0/5 end) limit 1;
    -- A weighted selection across 50 creatures reproduces the catalog rarity percentages.
  end if;
  if not found then raise exception 'Creature catalog is empty'; end if;
  if v_pick.is_cursed then
    insert into public.creature_inventory(family_id,user_id,creature_id,creature_name,rarity,is_cursed) values(v_member.family_id,auth.uid(),v_pick.creature_id,v_pick.creature_name,'Curse',true);
    insert into public.chores(family_id,kind,title,description,difficulty,xp_reward,token_reward,deadline_at,created_by)
    values(v_member.family_id,'curse',v_pick.creature_name,v_pick.curse_task,case when v_pick.creature_name='Dreadlord' then 'Svår' else 'Lätt' end,0,0,now()+make_interval(hours=>v_pick.deadline_hours),auth.uid()) returning id into v_chore;
    insert into public.chore_assignments(family_id,chore_id,user_id,assigned_by) values(v_member.family_id,v_chore,auth.uid(),auth.uid());
    if v_pick.steals_tokens>0 then update public.family_members set tokens=greatest(0,tokens-least(v_pick.steals_tokens,tokens)) where family_id=v_member.family_id and user_id=auth.uid(); end if;
  else
    select exists(select 1 from public.creature_inventory where family_id=v_member.family_id and user_id=auth.uid() and creature_id=v_pick.creature_id and not is_cursed) into v_dup;
    if v_dup then
      v_shards:=case v_pick.rarity when 'Common' then 5 when 'Uncommon' then 10 when 'Rare' then 20 when 'Epic' then 35 else 50 end;
      update public.family_members set shards=shards+v_shards where family_id=v_member.family_id and user_id=auth.uid();
    else
      insert into public.creature_inventory(family_id,user_id,creature_id,creature_name,rarity) values(v_member.family_id,auth.uid(),v_pick.creature_id,v_pick.creature_name,v_pick.rarity);
    end if;
  end if;
  select jsonb_build_object('creature_id',v_pick.creature_id,'creature_name',v_pick.creature_name,'rarity',v_pick.rarity,'is_cursed',v_pick.is_cursed,'is_duplicate',v_dup,'shards_awarded',v_shards,'curse_task',v_pick.curse_task,'deadline_hours',v_pick.deadline_hours,'tokens',m.tokens,'shards',m.shards) into v_existing from public.family_members m where m.family_id=v_member.family_id and m.user_id=auth.uid();
  update public.creature_chest_openings set result=v_existing where id=v_opening;
  return v_existing;
end $$;
revoke all on function public.open_creature_chest(uuid,text,uuid) from public,anon;
grant execute on function public.open_creature_chest(uuid,text,uuid) to authenticated;
notify pgrst, 'reload schema';
