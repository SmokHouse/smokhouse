-- =====================================================================
--  Smok'house — factures, numérotation continue, livre des recettes
--  À coller UNE fois dans Supabase > SQL Editor > New query > Run
--  (après supabase-setup.sql et ventes-setup.sql).
--  Ne supprime aucune donnée. Peut être relancé sans risque.
-- =====================================================================

-- 1) Infos de l'entreprise imprimées sur les factures (une seule ligne)
create table if not exists public.entreprise (
  id               int primary key default 1 check (id = 1),
  nom_legal        text not null default '',          -- ex : Timéo DUPONT
  nom_commercial   text not null default 'Smok''house',
  adresse          text not null default '',          -- n° et rue
  code_postal      text not null default '43000',
  ville            text not null default 'Le Puy-en-Velay',
  siret            text not null default '10317445400019',
  email            text not null default '',
  telephone        text not null default '',
  delai_paiement_pro int not null default 30,          -- jours, clients pros
  updated_at       timestamptz not null default now()
);
insert into public.entreprise (id) values (1) on conflict (id) do nothing;
alter table public.entreprise enable row level security;
drop policy if exists entreprise_admin_all on public.entreprise;
create policy entreprise_admin_all on public.entreprise
  for all using (public.is_admin()) with check (public.is_admin());

-- 2) Encaissement (pour le livre des recettes)
alter table public.manual_sales add column if not exists client  text;
alter table public.manual_sales add column if not exists paid_at date;   -- null = pas encore encaissé (crédit)
alter table public.orders       add column if not exists payment text;   -- especes / carte / virement / credit / autre
alter table public.orders       add column if not exists paid_at date;

-- Ventes déjà enregistrées : encaissées le jour de la vente, sauf crédit
update public.manual_sales set paid_at = sale_date where paid_at is null and payment <> 'credit';
update public.orders set paid_at = (coalesce(completed_at, created_at) at time zone 'Europe/Paris')::date,
                         payment = coalesce(payment, 'autre')
 where status = 'terminee' and paid_at is null;

-- Nouvelle vente hors site : encaissée le jour même, sauf crédit
create or replace function public.manual_sale_paid_default()
returns trigger language plpgsql as $$
begin
  if new.paid_at is null and coalesce(new.payment, '') <> 'credit' then new.paid_at := new.sale_date; end if;
  return new;
end; $$;
drop trigger if exists manual_sale_paid_default on public.manual_sales;
create trigger manual_sale_paid_default before insert on public.manual_sales
  for each row execute function public.manual_sale_paid_default();

-- 3) Compteur de numérotation (un par année, sans trou)
create table if not exists public.facture_compteurs (
  annee   int primary key,
  dernier int not null default 0
);
alter table public.facture_compteurs enable row level security;   -- aucune policy : seules les fonctions y touchent

-- 4) Factures et avoirs
create table if not exists public.factures (
  id              bigserial primary key,
  numero          text not null unique,                -- SH-2026-0001
  annee           int not null,
  rang            int not null,
  type            text not null default 'facture' check (type in ('facture', 'avoir')),
  facture_origine text,                                -- pour un avoir : n° de la facture annulée
  motif           text,                                -- pour un avoir
  date_emission   date not null,
  date_vente      date not null,
  source          text not null check (source in ('commande', 'vente_manuelle', 'libre')),
  source_ref      text,                                -- id de la commande ou de la vente
  client          jsonb not null,                      -- {nom, adresse, pro, raison_sociale, siren, adresse_livraison, email}
  lignes          jsonb not null,                      -- [{designation, quantite, unite, prix_unitaire, total}]
  total           numeric(10,2) not null,
  mode_paiement   text,
  date_echeance   date,                                -- clients pros
  emetteur        jsonb not null,                      -- copie figée des infos entreprise
  created_at      timestamptz not null default now(),
  unique (annee, rang)
);
create index if not exists factures_source_idx on public.factures (source, source_ref);

alter table public.factures enable row level security;
drop policy if exists factures_admin_select on public.factures;
create policy factures_admin_select on public.factures for select using (public.is_admin());
-- Pas de policy insert/update/delete : on passe uniquement par les fonctions ci-dessous.
grant select on public.factures to authenticated;
grant select, insert, update on public.entreprise to authenticated;

-- Une facture émise est définitive : ni modification, ni suppression (même depuis l'éditeur SQL)
create or replace function public.factures_verrou()
returns trigger language plpgsql as $$
begin
  raise exception 'FACTURE_VERROUILLEE : une facture émise ne peut être ni modifiée ni supprimée. Émets un avoir.';
end; $$;
drop trigger if exists factures_verrou_row on public.factures;
create trigger factures_verrou_row before update or delete on public.factures
  for each row execute function public.factures_verrou();
drop trigger if exists factures_verrou_truncate on public.factures;
create trigger factures_verrou_truncate before truncate on public.factures
  for each statement execute function public.factures_verrou();

-- Prochain numéro (verrou de ligne : deux factures simultanées ne peuvent pas avoir le même n°,
-- et si l'émission échoue, la transaction est annulée et le numéro n'est pas consommé)
create or replace function public.facture_prochain_rang(p_annee int)
returns int language plpgsql security definer set search_path = public as $$
declare r int;
begin
  insert into public.facture_compteurs (annee, dernier) values (p_annee, 0) on conflict (annee) do nothing;
  update public.facture_compteurs set dernier = dernier + 1 where annee = p_annee returning dernier into r;
  return r;
end; $$;
revoke all on function public.facture_prochain_rang(int) from public, anon, authenticated;

-- 5) Émettre une facture
create or replace function public.emettre_facture(
  p_source text, p_source_ref text, p_client jsonb, p_lignes jsonb,
  p_date_vente date, p_mode_paiement text)
returns table (id bigint, numero text)
language plpgsql security definer set search_path = public as $$
declare
  e record; l jsonb; lignes_ok jsonb := '[]'::jsonb; tot numeric := 0;
  q numeric; t numeric; an int; rg int; num text; today date; new_id bigint; pro boolean;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;

  select * into e from public.entreprise where entreprise.id = 1;
  if e is null or btrim(e.nom_legal) = '' or btrim(e.adresse) = '' then
    raise exception 'ENTREPRISE_INCOMPLETE';
  end if;

  if p_source not in ('commande', 'vente_manuelle', 'libre') then raise exception 'SOURCE_INVALIDE'; end if;
  if coalesce(btrim(p_client->>'nom'), '') = '' then raise exception 'CLIENT_MANQUANT'; end if;
  pro := coalesce((p_client->>'pro')::boolean, false);

  -- Déjà facturée (et pas annulée par un avoir) ?
  if p_source <> 'libre' and exists (
      select 1 from public.factures f
       where f.source = p_source and f.source_ref = p_source_ref and f.type = 'facture'
         and not exists (select 1 from public.factures a where a.type = 'avoir' and a.facture_origine = f.numero)) then
    raise exception 'DEJA_FACTUREE';
  end if;

  if jsonb_typeof(p_lignes) <> 'array' or jsonb_array_length(p_lignes) = 0 then raise exception 'LIGNES_VIDES'; end if;
  for l in select * from jsonb_array_elements(p_lignes) loop
    q := (l->>'quantite')::numeric; t := round((l->>'total')::numeric, 2);
    if coalesce(btrim(l->>'designation'), '') = '' or q is null or q <= 0 or t is null or t < 0 then
      raise exception 'LIGNE_INVALIDE';
    end if;
    lignes_ok := lignes_ok || jsonb_build_object(
      'designation', btrim(l->>'designation'), 'quantite', q, 'unite', coalesce(l->>'unite', 'g'),
      'prix_unitaire', round(t / q, 4), 'total', t);
    tot := tot + t;
  end loop;
  if tot <= 0 then raise exception 'TOTAL_NUL'; end if;

  today := (now() at time zone 'Europe/Paris')::date;
  an := extract(year from today)::int;
  rg := public.facture_prochain_rang(an);
  num := 'SH-' || an || '-' || lpad(rg::text, 4, '0');

  insert into public.factures (numero, annee, rang, type, date_emission, date_vente, source, source_ref,
                               client, lignes, total, mode_paiement, date_echeance, emetteur)
  values (num, an, rg, 'facture', today, coalesce(p_date_vente, today), p_source, p_source_ref,
          p_client, lignes_ok, round(tot, 2), nullif(p_mode_paiement, ''),
          case when pro then today + e.delai_paiement_pro end,
          jsonb_build_object('nom_legal', e.nom_legal, 'nom_commercial', e.nom_commercial, 'adresse', e.adresse,
                             'code_postal', e.code_postal, 'ville', e.ville, 'siret', e.siret,
                             'email', e.email, 'telephone', e.telephone, 'delai_paiement_pro', e.delai_paiement_pro))
  returning factures.id into new_id;

  return query select new_id, num;
end; $$;
grant execute on function public.emettre_facture(text, text, jsonb, jsonb, date, text) to authenticated;

-- 6) Annuler une facture par un avoir (même numérotation)
create or replace function public.emettre_avoir(p_facture bigint, p_motif text)
returns table (id bigint, numero text)
language plpgsql security definer set search_path = public as $$
declare f record; an int; rg int; num text; today date; new_id bigint; neg jsonb;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  select * into f from public.factures where factures.id = p_facture;
  if f is null or f.type <> 'facture' then raise exception 'FACTURE_INTROUVABLE'; end if;
  if exists (select 1 from public.factures a where a.type = 'avoir' and a.facture_origine = f.numero) then
    raise exception 'DEJA_ANNULEE';
  end if;

  select jsonb_agg(jsonb_set(jsonb_set(x, '{total}', to_jsonb(-(x->>'total')::numeric)),
                             '{prix_unitaire}', to_jsonb(-(x->>'prix_unitaire')::numeric)))
    into neg from jsonb_array_elements(f.lignes) x;

  today := (now() at time zone 'Europe/Paris')::date;
  an := extract(year from today)::int;
  rg := public.facture_prochain_rang(an);
  num := 'SH-' || an || '-' || lpad(rg::text, 4, '0');

  insert into public.factures (numero, annee, rang, type, facture_origine, motif, date_emission, date_vente,
                               source, source_ref, client, lignes, total, mode_paiement, emetteur)
  values (num, an, rg, 'avoir', f.numero, nullif(btrim(p_motif), ''), today, f.date_vente,
          f.source, f.source_ref, f.client, neg, -f.total, f.mode_paiement, f.emetteur)
  returning factures.id into new_id;

  return query select new_id, num;
end; $$;
grant execute on function public.emettre_avoir(bigint, text) to authenticated;

-- Vérification
select 'Factures prêtes' as statut,
       (select count(*) from public.factures) as factures_existantes,
       (select nom_legal from public.entreprise where id = 1) as nom_legal;
