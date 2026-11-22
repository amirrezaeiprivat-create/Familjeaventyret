-- Assign each scheduled weekday occurrence to one responsible family member.
alter table public.chore_assignments add column if not exists scheduled_for date;
create or replace function public.add_assigned_weekly_chores(p_plan_id uuid,p_title text,p_description text,p_xp integer,p_tokens integer,p_difficulty text,p_schedule jsonb)
returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_plan public.weekly_plans%rowtype; v_item jsonb; v_day integer; v_day_name text; v_member uuid; v_chore uuid; v_date date;
begin
 if auth.uid() is null then raise exception 'Logga in för att fortsätta.'; end if;
 select * into v_plan from public.weekly_plans where id=p_plan_id for update;
 if not found or not public.app_is_family_admin(v_plan.family_id) then raise exception 'Veckoplanen hittades inte eller så saknas administratörsbehörighet.'; end if;
 if v_plan.week_start<>date_trunc('week',now() at time zone 'Europe/Stockholm')::date+7 then raise exception 'Du kan bara planera sysslor för nästa vecka.'; end if;
 if v_plan.status<>'open' then raise exception 'Planen för nästa vecka är stängd.'; end if;
 if length(trim(coalesce(p_title,'')))<1 or length(trim(p_title))>85 then raise exception 'Ange ett sysslenamn med 1 till 85 tecken.'; end if;
 if p_difficulty not in ('Lätt','Mellan','Svår') then raise exception 'Ogiltig svårighetsgrad.'; end if;
 if p_xp is null or p_xp<0 or p_xp>500 or p_tokens is null or p_tokens<0 or p_tokens>100 then raise exception 'Ogiltig XP- eller myntbelöning.'; end if;
 if jsonb_typeof(p_schedule) is distinct from 'array' then raise exception 'Välj minst en veckodag och ansvarig person.'; end if;
 if jsonb_array_length(p_schedule) not between 1 and 7 then raise exception 'Välj minst en veckodag och ansvarig person.'; end if;
 if exists(select 1 from jsonb_array_elements(p_schedule) as item(value) group by item.value->>'day' having count(*)>1) then raise exception 'Varje veckodag kan bara tilldelas en gång.'; end if;
 for v_item in select value from jsonb_array_elements(p_schedule) loop
  begin v_day:=(v_item->>'day')::integer; v_member:=(v_item->>'user_id')::uuid;
  exception when others then raise exception 'Ogiltig dag eller familjemedlem i schemat.'; end;
  if v_day not between 1 and 7 then raise exception 'Välj en giltig veckodag.'; end if;
  if not exists(select 1 from public.family_members where family_id=v_plan.family_id and user_id=v_member and is_active) then raise exception 'Varje ansvarig måste vara en aktiv familjemedlem.'; end if;
  v_day_name:=case v_day when 1 then 'måndag' when 2 then 'tisdag' when 3 then 'onsdag' when 4 then 'torsdag' when 5 then 'fredag' when 6 then 'lördag' else 'söndag' end;
  v_date:=v_plan.week_start+v_day-1;
  insert into public.chores(family_id,plan_id,title,description,difficulty,xp_reward,token_reward,created_by)
  values(v_plan.family_id,v_plan.id,trim(p_title)||' · '||v_day_name,coalesce(trim(p_description),''),p_difficulty,p_xp,p_tokens,auth.uid()) returning id into v_chore;
  insert into public.chore_assignments(family_id,chore_id,user_id,assigned_by,scheduled_for) values(v_plan.family_id,v_chore,v_member,auth.uid(),v_date);
 end loop;
 return jsonb_array_length(p_schedule);
end $$;
create or replace function public.enforce_scheduled_chore_day()
returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_scheduled date;
begin
 select scheduled_for into v_scheduled from public.chore_assignments where chore_id=new.chore_id and user_id=new.user_id;
 if v_scheduled is not null and v_scheduled>(now() at time zone 'Europe/Stockholm')::date then raise exception 'Den här sysslan är planerad till en senare dag.'; end if;
 return new;
end $$;
drop trigger if exists quest_submission_scheduled_day on public.quest_submissions;
create trigger quest_submission_scheduled_day before insert on public.quest_submissions for each row execute function public.enforce_scheduled_chore_day();
revoke all on function public.add_assigned_weekly_chores(uuid,text,text,integer,integer,text,jsonb) from public,anon;
grant execute on function public.add_assigned_weekly_chores(uuid,text,text,integer,integer,text,jsonb) to authenticated;
revoke all on function public.enforce_scheduled_chore_day() from public,anon,authenticated;
notify pgrst,'reload schema';