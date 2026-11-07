-- =====================================================================
--  Smok'house — ajouter un client fidélité à la main (sans compte en ligne)
--  • Le client reçoit une carte SH-xxxxxx et cumule des points comme les autres.
--  • S'il crée plus tard un compte sur le site avec le même email, sa carte,
--    ses points et ta note privée sont automatiquement rattachés à son compte.
--  À coller dans Supabase > SQL Editor > New query > Run. Ne supprime aucune donnée.
-- =====================================================================

alter table public.profiles add column if not exists is_manual boolean not null default false;
alter table public.profiles add column if not exists phone text;
-- Un client ajouté à la main peut ne pas avoir d'email
alter table public.profiles alter column email drop not null;

-- Un client ajouté à la main n'a pas de compte de connexion : on retire le lien
-- obligatoire « fiche client = compte de connexion » s'il existe (aucune donnée touchée).
do $$
declare c record;
begin
  for c in select conname from pg_constraint
            where conrelid = 'public.profiles'::regclass and contype = 'f'
              and confrelid = 'auth.users'::regclass
  loop
    execute format('alter table public.profiles drop constraint %I', c.conname);
  end loop;
end $$;

-- Créer un client (admin uniquement) → renvoie son numéro de carte
create or replace function public.admin_creer_client(p_nom text, p_email text default null, p_tel text default null, p_points int default 0)
returns text
language plpgsql security definer set search_path = public as $$
declare num text; tries int := 0; mail text := nullif(lower(btrim(coalesce(p_email, ''))), '');
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if coalesce(btrim(p_nom), '') = '' then raise exception 'NOM_MANQUANT'; end if;
  if mail is not null and exists (select 1 from public.profiles where lower(email) = mail) then
    raise exception 'EMAIL_EXISTE';
  end if;
  loop
    num := 'SH-' || (floor(random() * 900000) + 100000)::int;
    exit when not exists (select 1 from public.profiles where member_number = num);
    tries := tries + 1; if tries > 50 then raise exception 'NUMERO_INDISPONIBLE'; end if;
  end loop;
  insert into public.profiles (id, name, email, phone, member_number, points, is_admin, is_manual)
  values (gen_random_uuid(), btrim(p_nom), mail, nullif(btrim(coalesce(p_tel, '')), ''),
          num, greatest(coalesce(p_points, 0), 0), false, true);
  return num;
end; $$;
grant execute on function public.admin_creer_client(text, text, text, int) to authenticated;

-- Modifier le nom / email / téléphone d'un client ajouté à la main (admin uniquement)
create or replace function public.admin_modifier_client(p_member text, p_nom text, p_email text, p_tel text)
returns void
language plpgsql security definer set search_path = public as $$
declare mail text := nullif(lower(btrim(coalesce(p_email, ''))), '');
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if coalesce(btrim(p_nom), '') = '' then raise exception 'NOM_MANQUANT'; end if;
  if mail is not null and exists (select 1 from public.profiles where lower(email) = mail and member_number <> p_member) then
    raise exception 'EMAIL_EXISTE';
  end if;
  update public.profiles set name = btrim(p_nom), email = mail, phone = nullif(btrim(coalesce(p_tel, '')), '')
   where member_number = p_member and is_manual;
  if not found then raise exception 'CLIENT_INTROUVABLE'; end if;
end; $$;
grant execute on function public.admin_modifier_client(text, text, text, text) to authenticated;

-- Quand ce client crée son compte sur le site avec le même email :
-- il récupère sa carte, ses points et la note privée, et la fiche manuelle disparaît.
create or replace function public.profiles_fusion_client_manuel()
returns trigger
language plpgsql security definer set search_path = public as $$
declare m record;
begin
  if new.is_manual or new.email is null then return new; end if;
  select * into m from public.profiles
   where is_manual and lower(email) = lower(new.email) and id <> new.id
   order by points desc limit 1;
  if m is null then return new; end if;

  begin
    update public.client_notes set customer_id = new.id
     where customer_id = m.id and not exists (select 1 from public.client_notes where customer_id = new.id);
  exception when undefined_table then null;   -- notes privées pas encore installées
  end;
  delete from public.profiles where id = m.id;
  update public.profiles
     set points = coalesce(points, 0) + coalesce(m.points, 0),
         member_number = m.member_number,
         phone = coalesce(phone, m.phone)
   where id = new.id;
  return new;
end; $$;
drop trigger if exists zz_profiles_fusion_client_manuel on public.profiles;
create trigger zz_profiles_fusion_client_manuel after insert on public.profiles
  for each row execute function public.profiles_fusion_client_manuel();

select 'Clients manuels prêts' as statut;
