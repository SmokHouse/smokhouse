-- =====================================================================
--  Smok'house — BOUTIQUE EN LIGNE (livraison locale + expédition France)
--  • Deux modes de commande : « local » (vélo/scooter, jour même, 43) et « france » (colis)
--  • Prix, frais de port, totaux et stock recalculés / vérifiés côté serveur
--  • Fiches produits (poids, lot, cannabinoïdes, lien COA) et grille de prix en base
--  • Paiement en ligne générique (table paiements) + factures automatiques
--  À coller dans Supabase > SQL Editor > New query > Run, APRÈS tous les autres fichiers .sql.
--  Ne supprime aucune donnée. Peut être relancé sans risque.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Commandes : nouvelles colonnes
-- ---------------------------------------------------------------------
alter table public.orders add column if not exists mode               text not null default 'local';  -- 'local' ou 'france'
alter table public.orders add column if not exists shipping_method    text;          -- 'domicile' ou 'relais' (France)
alter table public.orders add column if not exists shipping_cost      numeric(10,2) not null default 0;
alter table public.orders add column if not exists subtotal           numeric(10,2);  -- total produits (hors port)
alter table public.orders add column if not exists lignes_json        jsonb;          -- détail figé : [{product_id, designation, grammes, prix_g, total, lot}]
alter table public.orders add column if not exists ship_address       jsonb;          -- {nom, ligne1, ligne2, cp, ville, pays}
alter table public.orders add column if not exists relay_point        jsonb;          -- {id, nom, adresse, cp, ville}
alter table public.orders add column if not exists customer_email     text;
alter table public.orders add column if not exists postal_code        text;
alter table public.orders add column if not exists carrier            text;
alter table public.orders add column if not exists tracking_number    text;
alter table public.orders add column if not exists tracking_url       text;
alter table public.orders add column if not exists payment_status     text not null default 'none'; -- none / pending / paid / failed / refunded
alter table public.orders add column if not exists payment_ref        text;
alter table public.orders add column if not exists payment_provider   text;
alter table public.orders add column if not exists shipped_at         timestamptz;
alter table public.orders add column if not exists confirmation_sent_at timestamptz;
alter table public.orders add column if not exists tracking_sent_at   timestamptz;
alter table public.orders add column if not exists invoice_sent_at    timestamptz;
alter table public.orders add column if not exists facture_erreur     text;          -- si la facture automatique n'a pas pu être émise
alter table public.orders add column if not exists updated_at         timestamptz;
alter table public.orders add column if not exists remise             numeric(10,2) not null default 0;  -- remise accordée à la main par l'admin
alter table public.orders add column if not exists remise_motif       text;

do $$ begin
  alter table public.orders add constraint orders_mode_chk check (mode in ('local', 'france'));
exception when duplicate_object then null; end $$;

create index if not exists orders_mode_status_idx on public.orders (mode, status);

-- ---------------------------------------------------------------------
-- 2) Fiches produits + grille de prix (lecture publique, modif admin)
-- ---------------------------------------------------------------------
create table if not exists public.menu_produits (
  product_id text primary key,
  nom        text not null,
  categorie  text not null default 'fleur' check (categorie in ('fleur', 'resine')),
  profil     text check (profil in ('indica', 'sativa', 'hybride')),
  taux       text,
  aromes     text,
  photo_url  text,
  nouveau    boolean not null default false,
  top_vente  boolean not null default false,
  visible    boolean not null default true,
  prix_1g    numeric(10,2),
  ordre      int not null default 100,
  updated_at timestamptz not null default now()
);
alter table public.menu_produits add column if not exists description   text;
alter table public.menu_produits add column if not exists lot           text;            -- n° de lot
alter table public.menu_produits add column if not exists cbd_pct       numeric(5,2);
alter table public.menu_produits add column if not exists thc_pct       numeric(5,3);    -- Δ9-THC
alter table public.menu_produits add column if not exists thv_pct       numeric(5,2);
alter table public.menu_produits add column if not exists cbg_pct       numeric(5,2);
alter table public.menu_produits add column if not exists coa_url       text;            -- lien du certificat d'analyse
alter table public.menu_produits add column if not exists poids_options jsonb;           -- grammages proposés, ex [1,3,5,10]
alter table public.menu_produits add column if not exists expediable    boolean not null default true;
alter table public.menu_produits add column if not exists prix_paliers  jsonb;           -- [[1,9],[3,8.5],[5,8],[50,7]] = à partir de X g → Y €/g

insert into public.menu_produits (product_id, nom, categorie, taux, ordre) values
  ('superlemonhaze', 'SuperLemon Haze', 'fleur',  'THV 40 %', 10),
  ('ogkush',         'OG Kush',         'fleur',  'THV 40 %', 20),
  ('piatella',       'Piatella',        'resine', 'THV 60 %', 30),
  ('caliplate',      'Cali Plate',      'resine', 'THV 80 %', 40),
  ('caligazberry',   'CaliGaz Berry',   'resine', 'THV 80 %', 50),
  ('manali',         'Manali',          'resine', 'THV 80 %', 60),
  ('bananadry',      'Banana Dry',      'resine', 'THV 50 %', 70)
on conflict (product_id) do nothing;

-- Grille actuelle du site (uniquement si pas encore renseignée)
update public.menu_produits set prix_paliers = '[[1,9],[3,8.5],[5,8],[50,7]]'::jsonb
 where prix_paliers is null and product_id in ('superlemonhaze', 'ogkush', 'piatella', 'bananadry');
update public.menu_produits set prix_paliers = '[[1,10],[25,9]]'::jsonb
 where prix_paliers is null and product_id in ('caliplate', 'manali', 'caligazberry', 'calibanana');
update public.menu_produits set thv_pct = v.t, coa_url = coalesce(coa_url, '/coa-' || product_id || '.pdf'),
       poids_options = coalesce(poids_options, '[1,3,5,10]'::jsonb), thc_pct = coalesce(thc_pct, 0.3)
  from (values ('superlemonhaze', 40), ('ogkush', 40), ('piatella', 60), ('caliplate', 80),
               ('caligazberry', 80), ('manali', 80), ('bananadry', 50)) as v(id, t)
 where product_id = v.id and thv_pct is null;

alter table public.menu_produits enable row level security;
grant select on public.menu_produits to anon, authenticated;
drop policy if exists menu_produits_lecture on public.menu_produits;
create policy menu_produits_lecture on public.menu_produits for select using (true);
drop policy if exists menu_produits_admin on public.menu_produits;
create policy menu_produits_admin on public.menu_produits for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- 3) Réglages expédition France (désactivée tant que tu n'as pas validé un transporteur)
-- ---------------------------------------------------------------------
create table if not exists public.expedition_config (
  id                    int primary key default 1 check (id = 1),
  actif                 boolean not null default false,
  prix_domicile         numeric(10,2) not null default 5.90,
  prix_relais           numeric(10,2) not null default 4.90,
  seuil_gratuit         numeric(10,2) not null default 50,     -- port offert dès ce montant (0 = jamais)
  relais_actif          boolean not null default true,
  domicile_actif        boolean not null default true,
  transporteur          text not null default '',              -- ex : Colissimo, Mondial Relay
  tracking_url_template text not null default '',              -- ex : https://www.laposte.fr/outils/suivre-vos-envois?code={suivi}
  delai                 text not null default '48 à 72 h ouvrées après paiement',
  relais_recherche_url  text not null default '',              -- page « trouver un point relais » du transporteur
  updated_at            timestamptz not null default now()
);
alter table public.expedition_config add column if not exists relais_recherche_url text not null default '';
insert into public.expedition_config (id) values (1) on conflict (id) do nothing;
alter table public.expedition_config enable row level security;
grant select on public.expedition_config to anon, authenticated;
drop policy if exists expedition_config_lecture on public.expedition_config;
create policy expedition_config_lecture on public.expedition_config for select using (true);
drop policy if exists expedition_config_admin on public.expedition_config;
create policy expedition_config_admin on public.expedition_config for all using (public.is_admin()) with check (public.is_admin());

-- ---------------------------------------------------------------------
-- 4) Paiements en ligne et journal des e-mails (admin seulement)
-- ---------------------------------------------------------------------
create table if not exists public.paiements (
  id           bigserial primary key,
  order_id     text not null,
  provider     text not null,
  provider_ref text,                       -- identifiant du paiement chez le prestataire
  event_id     text unique,                -- anti-doublon des webhooks
  montant      numeric(10,2) not null,
  devise       text not null default 'EUR',
  statut       text not null,              -- created / paid / failed / refunded
  details      jsonb,
  created_at   timestamptz not null default now()
);
create index if not exists paiements_order_idx on public.paiements (order_id);

create table if not exists public.emails_envoyes (
  id         bigserial primary key,
  order_id   text,
  type       text not null,                -- confirmation / paiement / expedition / facture
  destinataire text,
  ok         boolean not null,
  erreur     text,
  created_at timestamptz not null default now()
);

alter table public.paiements enable row level security;
alter table public.emails_envoyes enable row level security;
drop policy if exists paiements_admin on public.paiements;
create policy paiements_admin on public.paiements for select using (public.is_admin());
drop policy if exists emails_admin on public.emails_envoyes;
create policy emails_admin on public.emails_envoyes for select using (public.is_admin());
revoke insert, update, delete on public.paiements, public.emails_envoyes from anon, authenticated;

-- ---------------------------------------------------------------------
-- 5) Prix et frais de port (source de vérité = la base)
-- ---------------------------------------------------------------------
create or replace function public.prix_gramme(p_product text, p_grams numeric)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare t jsonb; e jsonb; r numeric; b numeric;
begin
  select prix_paliers into t from public.menu_produits where product_id = p_product;
  if t is not null and jsonb_typeof(t) = 'array' and jsonb_array_length(t) > 0 then
    for e in select value from jsonb_array_elements(t) order by (value->>0)::numeric loop
      if r is null or p_grams >= (e->>0)::numeric then r := (e->>1)::numeric; end if;
    end loop;
    return r;
  end if;
  select coalesce(nullif(base_price, 0), (select prix_1g from public.menu_produits where product_id = p_product))
    into b from public.products where id = p_product;
  return b;
end; $$;
grant execute on function public.prix_gramme(text, numeric) to anon, authenticated, service_role;

create or replace function public.frais_port(p_methode text, p_sous_total numeric)
returns numeric language plpgsql stable security definer set search_path = public as $$
declare c record;
begin
  select * into c from public.expedition_config where id = 1;
  if c is null then return null; end if;
  if c.seuil_gratuit > 0 and p_sous_total >= c.seuil_gratuit then return 0; end if;
  if p_methode = 'relais' then return c.prix_relais; end if;
  if p_methode = 'domicile' then return c.prix_domicile; end if;
  return null;
end; $$;
grant execute on function public.frais_port(text, numeric) to anon, authenticated, service_role;

-- Grammes déjà réservés par des commandes en cours (pas encore retirées du stock)
create or replace function public.stock_reserve(p_product text, p_exclude text default null)
returns numeric language sql stable security definer set search_path = public as $$
  select coalesce(sum((o.items_json->>p_product)::numeric), 0)
    from public.orders o
   where o.items_json ? p_product and not o.stock_deducted
     and (p_exclude is null or o.id::text <> p_exclude)
     and (o.status in ('en_attente', 'en_cours', 'confirmee', 'en_livraison', 'payee', 'preparation')
          or (o.status = 'attente_paiement' and o.created_at > now() - interval '24 hours'));
$$;
revoke all on function public.stock_reserve(text, text) from public, anon, authenticated;
grant execute on function public.stock_reserve(text, text) to service_role;

-- Disponibilité publique : le site grise un produit si stock - réservations <= 0
create or replace function public.public_stock()
returns table (id text, available boolean)
language sql stable security definer set search_path = public as $$
  select p.id, (p.active and p.stock_grams - public.stock_reserve(p.id) > 0) from public.products p;
$$;
grant execute on function public.public_stock() to anon, authenticated;

-- ---------------------------------------------------------------------
-- 5 bis) PROMOS automatiques (appliquées par le serveur)
--   type « pourcent » : -X % sur un produit / une catégorie / tout, dès N grammes
--   type « lot »      : « X g pour Y € » (le prix au gramme du lot s'applique dès X g)
-- ---------------------------------------------------------------------
create table if not exists public.promos (
  id          bigserial primary key,
  nom         text not null,                       -- affiché au client, ex : « 10 g = 90 € »
  product_id  text,                                -- null = tous les produits (ou la catégorie)
  categorie   text check (categorie in ('fleur', 'resine')),
  type        text not null check (type in ('pourcent', 'lot')),
  pourcent    numeric(5,2),                        -- type pourcent : 10 = -10 %
  grammes     numeric(10,2),                       -- type lot : 10 (g)
  prix_lot    numeric(10,2),                       -- type lot : 90 (€)
  grammes_min numeric(10,2) not null default 0,    -- type pourcent : à partir de N g
  date_debut  date,
  date_fin    date,
  actif       boolean not null default true,
  created_at  timestamptz not null default now(),
  check ((type = 'pourcent' and pourcent > 0 and pourcent < 100) or (type = 'lot' and grammes > 0 and prix_lot > 0))
);
alter table public.promos enable row level security;
grant select on public.promos to anon, authenticated;
grant insert, update, delete on public.promos to authenticated;
grant usage, select on sequence public.promos_id_seq to authenticated;
drop policy if exists promos_lecture on public.promos;
create policy promos_lecture on public.promos for select using (
  actif and (date_debut is null or date_debut <= (now() at time zone 'Europe/Paris')::date)
        and (date_fin is null or date_fin >= (now() at time zone 'Europe/Paris')::date));
drop policy if exists promos_admin on public.promos;
create policy promos_admin on public.promos for all using (public.is_admin()) with check (public.is_admin());

-- Prix d'une ligne avec la meilleure promo en cours → {base, total, promo}
create or replace function public.prix_ligne(p_product text, p_grams numeric)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare px numeric; base numeric; best numeric; nom text; pr record; t numeric; cat text; today date := (now() at time zone 'Europe/Paris')::date;
begin
  px := public.prix_gramme(p_product, p_grams);
  if px is null then return null; end if;
  base := round(px * p_grams, 2); best := base;
  select coalesce(m.categorie, p.category) into cat from public.products p left join public.menu_produits m on m.product_id = p.id where p.id = p_product;
  for pr in select * from public.promos
             where actif and (date_debut is null or date_debut <= today) and (date_fin is null or date_fin >= today)
               and (product_id is null or product_id = p_product) and (categorie is null or categorie = cat) loop
    t := null;
    if pr.type = 'pourcent' and p_grams >= pr.grammes_min then t := round(base * (1 - pr.pourcent / 100), 2); end if;
    if pr.type = 'lot' and p_grams >= pr.grammes then t := round(p_grams * pr.prix_lot / pr.grammes, 2); end if;
    if t is not null and t < best then best := t; nom := pr.nom; end if;
  end loop;
  return jsonb_build_object('base', base, 'total', best, 'promo', nom, 'prix_g', px);
end; $$;
grant execute on function public.prix_ligne(text, numeric) to anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 6) Création d'une commande — appelée UNIQUEMENT par la Netlify Function (clé service)
--    Tout est recalculé ici : prix, port, total, stock, récompense fidélité.
-- ---------------------------------------------------------------------
create or replace function public.creer_commande_srv(p jsonb)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_mode text := p->>'mode';
  v_items jsonb := p->'items';
  v_user uuid := nullif(p->>'customer_id', '')::uuid;
  v_method text := nullif(p->>'shipping_method', '');
  v_reward int := nullif(p->>'reward_points', '')::int;
  k text; gr numeric; pr record; mp record; px numeric; dispo numeric;
  lignes jsonb := '[]'::jsonb; txt text := ''; sous_total numeric := 0; port numeric := 0;
  cfg record; rw record; solde int; new_id text; adr jsonb; rel jsonb; addr_txt text; o record;
  nb int := 0; v_carrier text; pl jsonb;
begin
  if v_mode not in ('local', 'france') then raise exception 'MODE_INVALIDE'; end if;
  if v_items is null or jsonb_typeof(v_items) <> 'object' or v_items = '{}'::jsonb then raise exception 'PANIER_VIDE'; end if;
  if coalesce(btrim(p->>'name'), '') = '' or coalesce(btrim(p->>'phone'), '') = '' then raise exception 'COORDONNEES_MANQUANTES'; end if;

  -- Verrouille les produits concernés (deux commandes simultanées ne peuvent pas vendre le même stock)
  perform 1 from public.products where id in (select jsonb_object_keys(v_items)) order by id for update;

  for k, gr in select key, value::numeric from jsonb_each_text(v_items) order by key loop
    nb := nb + 1;
    if nb > 20 then raise exception 'PANIER_TROP_GRAND'; end if;
    if gr is null or gr <= 0 or gr > 500 or gr <> round(gr, 1) then raise exception 'QUANTITE_INVALIDE:%', k; end if;
    select * into pr from public.products where id = k;
    if pr is null or not pr.active then raise exception 'PRODUIT_INDISPONIBLE:%', k; end if;
    select * into mp from public.menu_produits where product_id = k;
    if v_mode = 'france' and mp is not null and not mp.expediable then raise exception 'PRODUIT_NON_EXPEDIABLE:%', k; end if;
    px := public.prix_gramme(k, gr);
    if px is null or px <= 0 then raise exception 'PRIX_INCONNU:%', k; end if;
    dispo := pr.stock_grams - public.stock_reserve(k);
    if dispo < gr then raise exception 'STOCK_INSUFFISANT:%:%', k, greatest(floor(dispo), 0); end if;
    pl := public.prix_ligne(k, gr);
    lignes := lignes || jsonb_build_object('product_id', k, 'designation', coalesce(mp.nom, pr.name),
               'categorie', coalesce(mp.categorie, pr.category), 'grammes', gr, 'prix_g', px,
               'base', (pl->>'base')::numeric, 'total', (pl->>'total')::numeric, 'promo', pl->>'promo', 'lot', mp.lot);
    txt := txt || case when txt = '' then '' else ', ' end || trim(to_char(gr, 'FM999990.0')) || 'g ' || coalesce(mp.nom, pr.name)
           || ' (' || replace(to_char((pl->>'total')::numeric, 'FM999990.00'), '.', ',') || '€' || coalesce(' promo ' || (pl->>'promo'), '') || ')';
    sous_total := sous_total + (pl->>'total')::numeric;
  end loop;
  txt := replace(txt, '.0g ', 'g ');

  if v_mode = 'local' then
    if coalesce(btrim(p->>'address'), '') = '' then raise exception 'ADRESSE_MANQUANTE'; end if;
    if coalesce(p->>'postal_code', '') !~ '^43[0-9]{3}$' then raise exception 'HORS_ZONE'; end if;
    addr_txt := btrim(p->>'address') || ' — ' || (p->>'postal_code');
  else
    select * into cfg from public.expedition_config where id = 1;
    if cfg is null or not cfg.actif then raise exception 'EXPEDITION_INACTIVE'; end if;
    if v_method not in ('domicile', 'relais') then raise exception 'METHODE_INVALIDE'; end if;
    if (v_method = 'relais' and not cfg.relais_actif) or (v_method = 'domicile' and not cfg.domicile_actif) then raise exception 'METHODE_INVALIDE'; end if;
    if coalesce(p->>'customer_email', '') !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'EMAIL_MANQUANT'; end if;
    adr := p->'ship_address';
    if adr is null or coalesce(btrim(adr->>'nom'), '') = '' or coalesce(btrim(adr->>'ligne1'), '') = ''
       or coalesce(adr->>'cp', '') !~ '^[0-9]{5}$' or coalesce(btrim(adr->>'ville'), '') = '' then
      raise exception 'ADRESSE_INCOMPLETE';
    end if;
    adr := jsonb_build_object('nom', btrim(adr->>'nom'), 'ligne1', btrim(adr->>'ligne1'), 'ligne2', nullif(btrim(coalesce(adr->>'ligne2', '')), ''),
                              'cp', adr->>'cp', 'ville', btrim(adr->>'ville'), 'pays', 'France');
    if v_method = 'relais' then
      rel := p->'relay_point';
      if rel is null or coalesce(btrim(rel->>'nom'), '') = '' or coalesce(btrim(rel->>'adresse'), '') = '' or coalesce(rel->>'cp', '') !~ '^[0-9]{5}$' then
        raise exception 'RELAIS_MANQUANT';
      end if;
      rel := jsonb_build_object('id', left(coalesce(rel->>'id', ''), 40), 'nom', left(btrim(rel->>'nom'), 120), 'adresse', left(btrim(rel->>'adresse'), 200),
                                'cp', rel->>'cp', 'ville', left(btrim(coalesce(rel->>'ville', '')), 80));
      addr_txt := 'Point relais : ' || (rel->>'nom') || ', ' || (rel->>'adresse') || ', ' || (rel->>'cp') || ' ' || (rel->>'ville');
    else
      addr_txt := (adr->>'ligne1') || coalesce(', ' || (adr->>'ligne2'), '') || ', ' || (adr->>'cp') || ' ' || (adr->>'ville');
    end if;
    port := public.frais_port(v_method, sous_total);
    v_carrier := nullif(cfg.transporteur, '');
  end if;

  insert into public.orders (customer_id, customer_name, customer_phone, customer_email, delivery_mode, address, postal_code,
                             items, notes, status, items_json, lignes_json, subtotal, shipping_cost, total,
                             mode, shipping_method, ship_address, relay_point, payment_status, carrier, updated_at)
  values (v_user, left(btrim(p->>'name'), 80), left(btrim(p->>'phone'), 30), nullif(lower(btrim(coalesce(p->>'customer_email', ''))), ''),
          case when v_mode = 'local' then 'same_day_43' else 'france_' || v_method end,
          left(addr_txt, 400), case when v_mode = 'local' then p->>'postal_code' else adr->>'cp' end,
          txt || case when port > 0 then ' + port ' || replace(to_char(port, 'FM990.00'), '.', ',') || '€' else '' end
              || ' — Total : ' || replace(to_char(sous_total + port, 'FM999990.00'), '.', ',') || '€',
          nullif(left(btrim(coalesce(p->>'notes', '')), 500), ''),
          case when v_mode = 'local' then 'en_attente' else 'attente_paiement' end,
          v_items, lignes, sous_total, port, sous_total + port,
          v_mode, v_method, adr, rel, case when v_mode = 'local' then 'none' else 'pending' end,
          v_carrier, now())
  returning id::text into new_id;

  -- Récompense fidélité choisie au panier (points retirés tout de suite, rendus si annulation)
  if v_reward is not null and v_user is not null then
    select * into rw from public.fidelite_recompenses where points = v_reward and active;
    if rw is null then raise exception 'REWARD_NOT_FOUND'; end if;
    if sous_total < coalesce(rw.min_achat, 0) then raise exception 'MIN_ACHAT'; end if;
    update public.profiles set points = points - rw.points where id = v_user and points >= rw.points returning points into solde;
    if solde is null then raise exception 'NOT_ENOUGH_POINTS'; end if;
    insert into public.reward_redemptions (customer_id, reward_label, points_used, order_id)
    values (v_user, rw.label || ' (commande site)', rw.points, new_id);
    update public.orders set reward_points = rw.points, reward_label = rw.label where id::text = new_id;
  end if;

  select * into o from public.orders where id::text = new_id;
  return to_jsonb(o) || jsonb_build_object('id', new_id, 'points_restants', solde);
end; $$;
revoke all on function public.creer_commande_srv(jsonb) from public, anon, authenticated;
grant execute on function public.creer_commande_srv(jsonb) to service_role;

-- ---------------------------------------------------------------------
-- 7) Retrait du stock d'une commande (une seule fois)
-- ---------------------------------------------------------------------
create or replace function public.deduire_stock_commande(p_order text)
returns void language plpgsql security definer set search_path = public as $$
declare o record; k text; gr numeric;
begin
  select * into o from public.orders where id::text = p_order for update;
  if o is null or o.stock_deducted or o.items_json is null then return; end if;
  for k, gr in select key, value::numeric from jsonb_each_text(o.items_json) loop
    update public.products set stock_grams = greatest(0, stock_grams - gr), updated_at = now() where id = k;
    if found then
      insert into public.stock_movements (product_id, delta_grams, reason, order_id) values (k, -gr, 'vente', p_order);
    end if;
  end loop;
  update public.orders set stock_deducted = true, cost_total = coalesce(cost_total, public.items_cost(items_json)) where id::text = p_order;
end; $$;
revoke all on function public.deduire_stock_commande(text) from public, anon, authenticated;
grant execute on function public.deduire_stock_commande(text) to service_role;

-- ---------------------------------------------------------------------
-- 8) Changement de statut (transitions contrôlées, différentes selon le mode)
--    Local  : en_attente → confirmee → en_livraison → terminee (« Livrée »)   + annulee
--    France : attente_paiement → payee → preparation → expediee → terminee (« Livrée ») + annulee
-- ---------------------------------------------------------------------
create or replace function public.statut_commande_srv(p_order text, p_statut text, p_info jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o record; ok boolean; cfg record; suivi text; transp text; url text; cur text;
begin
  select * into o from public.orders where id::text = p_order for update;
  if o is null then raise exception 'ORDER_NOT_FOUND'; end if;
  cur := coalesce(o.status, 'en_attente');
  if cur = 'en_cours' then cur := 'confirmee'; end if;            -- ancien statut « validée »
  p_info := coalesce(p_info, '{}'::jsonb);

  if coalesce(o.mode, 'local') = 'local' then
    ok := (cur, p_statut) in (('en_attente','confirmee'), ('en_attente','annulee'),
                              ('confirmee','en_livraison'), ('confirmee','terminee'), ('confirmee','annulee'), ('confirmee','confirmee'),
                              ('en_livraison','terminee'), ('en_livraison','annulee'), ('en_livraison','confirmee'));
  else
    ok := (cur, p_statut) in (('attente_paiement','payee'), ('attente_paiement','annulee'),
                              ('payee','preparation'), ('payee','expediee'), ('payee','annulee'),
                              ('preparation','expediee'), ('preparation','annulee'), ('preparation','payee'),
                              ('expediee','terminee'), ('expediee','expediee'));
  end if;
  if not ok then raise exception 'TRANSITION_INTERDITE:%->%', cur, p_statut; end if;

  if p_statut = 'confirmee' then
    update public.orders set status = 'confirmee', delivery_time = coalesce(nullif(p_info->>'heure', ''), delivery_time), updated_at = now()
     where id::text = p_order;
  elsif p_statut = 'payee' then
    update public.orders set status = 'payee', payment_status = 'paid',
           payment = coalesce(nullif(p_info->>'payment', ''), payment, 'carte'),
           payment_ref = coalesce(nullif(p_info->>'ref', ''), payment_ref),
           payment_provider = coalesce(nullif(p_info->>'provider', ''), payment_provider),
           paid_at = coalesce(paid_at, (now() at time zone 'Europe/Paris')::date), updated_at = now()
     where id::text = p_order;
  elsif p_statut = 'expediee' then
    suivi := nullif(btrim(coalesce(p_info->>'tracking_number', '')), '');
    if suivi is null then raise exception 'SUIVI_MANQUANT'; end if;
    select * into cfg from public.expedition_config where id = 1;
    transp := coalesce(nullif(btrim(coalesce(p_info->>'carrier', '')), ''), o.carrier, nullif(cfg.transporteur, ''));
    url := nullif(btrim(coalesce(p_info->>'tracking_url', '')), '');
    if url is null and coalesce(cfg.tracking_url_template, '') <> '' then url := replace(cfg.tracking_url_template, '{suivi}', suivi); end if;
    perform public.deduire_stock_commande(p_order);
    update public.orders set status = 'expediee', tracking_number = suivi, carrier = transp, tracking_url = url,
           shipped_at = coalesce(shipped_at, now()), updated_at = now()
     where id::text = p_order;
  elsif p_statut = 'terminee' then
    perform public.deduire_stock_commande(p_order);
    update public.orders set status = 'terminee', completed_at = coalesce(completed_at, now()), updated_at = now()
     where id::text = p_order;
  else
    update public.orders set status = p_statut, updated_at = now() where id::text = p_order;
  end if;

  select * into o from public.orders where id::text = p_order;
  return to_jsonb(o) || jsonb_build_object('id', p_order);
end; $$;
revoke all on function public.statut_commande_srv(text, text, jsonb) from public, anon, authenticated;
grant execute on function public.statut_commande_srv(text, text, jsonb) to service_role;

-- Même chose depuis l'app admin (connecté en admin)
create or replace function public.admin_statut_commande(p_order text, p_statut text, p_info jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return public.statut_commande_srv(p_order, p_statut, p_info);
end; $$;
revoke all on function public.admin_statut_commande(text, text, jsonb) from public, anon;
grant execute on function public.admin_statut_commande(text, text, jsonb) to authenticated, service_role;

-- Paiement confirmé par le webhook : montant vérifié au centime, sans doublon
create or replace function public.marquer_payee_srv(p_order text, p_provider text, p_ref text, p_montant numeric, p_event text, p_details jsonb default null)
returns text language plpgsql security definer set search_path = public as $$
declare o record;
begin
  select * into o from public.orders where id::text = p_order for update;
  if o is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if p_event is not null and exists (select 1 from public.paiements where event_id = p_event) then return 'DEJA_TRAITE'; end if;
  if o.payment_status = 'paid' then
    insert into public.paiements (order_id, provider, provider_ref, event_id, montant, statut, details)
    values (p_order, p_provider, p_ref, p_event, p_montant, 'paid', p_details);
    return 'DEJA_PAYEE';
  end if;
  if round(p_montant, 2) <> round(o.total, 2) then
    insert into public.paiements (order_id, provider, provider_ref, event_id, montant, statut, details)
    values (p_order, p_provider, p_ref, null, p_montant, 'failed', jsonb_build_object('erreur', 'MONTANT_DIFFERENT', 'attendu', o.total, 'event', p_event) || coalesce(p_details, '{}'::jsonb));
    return 'MONTANT_DIFFERENT';   -- enregistré, la commande reste « en attente de paiement »
  end if;
  if o.status = 'annulee' then
    insert into public.paiements (order_id, provider, provider_ref, event_id, montant, statut, details)
    values (p_order, p_provider, p_ref, p_event, p_montant, 'paid', jsonb_build_object('alerte', 'COMMANDE_ANNULEE_A_REMBOURSER'));
    update public.orders set payment_status = 'paid', payment_ref = p_ref where id::text = p_order;
    return 'ANNULEE_A_REMBOURSER';
  end if;
  insert into public.paiements (order_id, provider, provider_ref, event_id, montant, statut, details)
  values (p_order, p_provider, p_ref, p_event, p_montant, 'paid', p_details);
  perform public.statut_commande_srv(p_order, 'payee', jsonb_build_object('ref', p_ref, 'provider', p_provider,
            'payment', case when p_provider = 'virement' then 'virement' else 'carte' end));
  return 'OK';
end; $$;
revoke all on function public.marquer_payee_srv(text, text, text, numeric, text, jsonb) from public, anon, authenticated;
grant execute on function public.marquer_payee_srv(text, text, text, numeric, text, jsonb) to service_role;

-- ---------------------------------------------------------------------
-- 9) Factures automatiques (numérotation continue SH-AAAA-NNNN, mentions légales)
--    Local : à la livraison (« Livrée »). France : au paiement.
-- ---------------------------------------------------------------------
-- Cœur de l'émission, sans contrôle admin (jamais appelable depuis le site)
create or replace function public.emettre_facture_core(
  p_source text, p_source_ref text, p_client jsonb, p_lignes jsonb, p_date_vente date, p_mode_paiement text)
returns table (id bigint, numero text)
language plpgsql security definer set search_path = public as $$
declare
  e record; l jsonb; lignes_ok jsonb := '[]'::jsonb; tot numeric := 0;
  q numeric; t numeric; an int; rg int; num text; today date; new_id bigint; pro boolean;
begin
  select * into e from public.entreprise where entreprise.id = 1;
  if e is null or btrim(e.nom_legal) = '' or btrim(e.adresse) = '' then raise exception 'ENTREPRISE_INCOMPLETE'; end if;
  if p_source not in ('commande', 'vente_manuelle', 'libre') then raise exception 'SOURCE_INVALIDE'; end if;
  if coalesce(btrim(p_client->>'nom'), '') = '' then raise exception 'CLIENT_MANQUANT'; end if;
  pro := coalesce((p_client->>'pro')::boolean, false);
  if p_source <> 'libre' and exists (
      select 1 from public.factures f
       where f.source = p_source and f.source_ref = p_source_ref and f.type = 'facture'
         and not exists (select 1 from public.factures a where a.type = 'avoir' and a.facture_origine = f.numero)) then
    raise exception 'DEJA_FACTUREE';
  end if;
  if jsonb_typeof(p_lignes) <> 'array' or jsonb_array_length(p_lignes) = 0 then raise exception 'LIGNES_VIDES'; end if;
  for l in select * from jsonb_array_elements(p_lignes) loop
    q := (l->>'quantite')::numeric; t := round((l->>'total')::numeric, 2);
    if coalesce(btrim(l->>'designation'), '') = '' or q is null or q <= 0 or t is null
       or (t < 0 and not coalesce((l->>'remise')::boolean, false)) then raise exception 'LIGNE_INVALIDE'; end if;
    lignes_ok := lignes_ok || jsonb_build_object('designation', btrim(l->>'designation'), 'quantite', q, 'unite', coalesce(l->>'unite', 'g'),
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
revoke all on function public.emettre_facture_core(text, text, jsonb, jsonb, date, text) from public, anon, authenticated;
grant execute on function public.emettre_facture_core(text, text, jsonb, jsonb, date, text) to service_role;

-- La fonction utilisée par l'app admin garde exactement le même comportement
create or replace function public.emettre_facture(
  p_source text, p_source_ref text, p_client jsonb, p_lignes jsonb, p_date_vente date, p_mode_paiement text)
returns table (id bigint, numero text)
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  return query select * from public.emettre_facture_core(p_source, p_source_ref, p_client, p_lignes, p_date_vente, p_mode_paiement);
end; $$;
grant execute on function public.emettre_facture(text, text, jsonb, jsonb, date, text) to authenticated;

-- Facture d'une commande du site (lignes figées à la commande + port + cadeau fidélité)
create or replace function public.facture_commande_srv(p_order text)
returns text language plpgsql security definer set search_path = public as $$
declare o record; lignes jsonb := '[]'::jsonb; l jsonb; k text; gr numeric; px numeric; cli jsonb; r record; dv date;
begin
  select * into o from public.orders where id::text = p_order;
  if o is null then raise exception 'ORDER_NOT_FOUND'; end if;
  select f.numero into r from public.factures f
   where f.source = 'commande' and f.source_ref = p_order and f.type = 'facture'
     and not exists (select 1 from public.factures a where a.type = 'avoir' and a.facture_origine = f.numero);
  if r is not null then return r.numero; end if;

  if o.lignes_json is not null and jsonb_array_length(o.lignes_json) > 0 then
    for l in select value from jsonb_array_elements(o.lignes_json) loop
      lignes := lignes || jsonb_build_object('designation', 'CBD ' || case when l->>'categorie' = 'resine' then 'résine' else 'fleur' end
                 || ' — ' || (l->>'designation') || coalesce(' (lot ' || nullif(l->>'lot', '') || ')', '') || coalesce(' — promo ' || nullif(l->>'promo', ''), ''),
                 'quantite', (l->>'grammes')::numeric, 'unite', 'g', 'total', (l->>'total')::numeric);
    end loop;
  elsif o.items_json is not null then
    for k, gr in select key, value::numeric from jsonb_each_text(o.items_json) loop
      if o.offert_json ? k then gr := gr - coalesce((o.offert_json->>k)::numeric, 0); end if;
      if gr <= 0 then continue; end if;
      px := coalesce(public.prix_gramme(k, gr), 0);
      lignes := lignes || jsonb_build_object('designation', 'CBD — ' || coalesce((select nom from public.menu_produits where product_id = k), k),
                                             'quantite', gr, 'unite', 'g', 'total', round(px * gr, 2));
    end loop;
  end if;
  if jsonb_array_length(lignes) = 0 then raise exception 'LIGNES_VIDES'; end if;

  if o.offert_json is not null and o.offert_json <> '{}'::jsonb then
    for k, gr in select key, value::numeric from jsonb_each_text(o.offert_json) loop
      lignes := lignes || jsonb_build_object('designation', 'Offert (ticket bonus) — ' || coalesce((select nom from public.menu_produits where product_id = k), k),
                                             'quantite', gr, 'unite', 'g', 'total', 0);
    end loop;
  end if;
  if coalesce(o.remise, 0) > 0 then
    lignes := lignes || jsonb_build_object('designation', 'Remise commerciale' || coalesce(' (' || nullif(o.remise_motif, '') || ')', ''),
                                           'quantite', 1, 'unite', 'u', 'total', -o.remise, 'remise', true);
  end if;
  if o.reward_label is not null and not o.reward_refunded then
    lignes := lignes || jsonb_build_object('designation', 'Cadeau fidélité : ' || o.reward_label, 'quantite', 1, 'unite', 'u', 'total', 0);
  end if;
  if coalesce(o.mode, 'local') = 'france' then
    lignes := lignes || jsonb_build_object('designation', 'Frais de port — ' || case when o.shipping_method = 'relais' then 'livraison en point relais' else 'livraison à domicile' end
                                           || coalesce(' (' || nullif(o.carrier, '') || ')', ''), 'quantite', 1, 'unite', 'u', 'total', coalesce(o.shipping_cost, 0));
  end if;

  cli := jsonb_build_object('nom', coalesce(nullif(o.ship_address->>'nom', ''), nullif(o.customer_name, ''), 'Client particulier'),
                            'adresse', case when o.mode = 'france' then concat_ws(', ', o.ship_address->>'ligne1', o.ship_address->>'ligne2',
                                            (o.ship_address->>'cp') || ' ' || (o.ship_address->>'ville')) else coalesce(o.address, '') end,
                            'email', o.customer_email, 'pro', false,
                            'adresse_livraison', case when o.shipping_method = 'relais' then o.address end);
  dv := case when o.mode = 'france' then coalesce(o.paid_at, (now() at time zone 'Europe/Paris')::date)
             else (coalesce(o.completed_at, now()) at time zone 'Europe/Paris')::date end;
  select * into r from public.emettre_facture_core('commande', p_order, cli, lignes, dv, coalesce(o.payment, case when o.mode = 'france' then 'carte' end));
  return r.numero;
end; $$;
revoke all on function public.facture_commande_srv(text) from public, anon, authenticated;
grant execute on function public.facture_commande_srv(text) to service_role;

create or replace function public.orders_facture_auto()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (coalesce(new.mode, 'local') = 'local' and new.status = 'terminee' and old.status is distinct from 'terminee')
     or (new.mode = 'france' and new.status = 'payee' and old.status is distinct from 'payee') then
    begin
      perform public.facture_commande_srv(new.id::text);
      update public.orders set facture_erreur = null where id = new.id and facture_erreur is not null;
    exception when others then
      -- La commande avance quand même ; l'admin voit pourquoi la facture manque (ex : infos entreprise incomplètes)
      update public.orders set facture_erreur = left(sqlerrm, 200) where id = new.id;
    end;
  end if;
  return null;
end; $$;
drop trigger if exists orders_facture_auto on public.orders;
create trigger orders_facture_auto after update of status on public.orders
  for each row execute function public.orders_facture_auto();

-- Rattrapage depuis l'app admin (ex : après avoir complété les infos entreprise)
create or replace function public.admin_facture_commande(p_order text)
returns text language plpgsql security definer set search_path = public as $$
declare n text;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  n := public.facture_commande_srv(p_order);
  update public.orders set facture_erreur = null where id::text = p_order;
  return n;
end; $$;
revoke all on function public.admin_facture_commande(text) from public, anon;
grant execute on function public.admin_facture_commande(text) to authenticated;

-- Le client peut lire SES factures (pour les télécharger dans son espace)
drop policy if exists factures_client_select on public.factures;
create policy factures_client_select on public.factures for select using (
  source = 'commande' and auth.uid() is not null
  and exists (select 1 from public.orders o where o.id::text = factures.source_ref and o.customer_id = auth.uid()));

-- ---------------------------------------------------------------------
-- 10) Fidélité : les points se calculent sur les produits (pas sur les frais de port)
-- ---------------------------------------------------------------------
create or replace function public.orders_fidelite_statut()
returns trigger language plpgsql security definer set search_path = public as $$
declare rate numeric; pts int;
begin
  if new.status = 'terminee' and old.status is distinct from 'terminee'
     and new.customer_id is not null and not old.points_credited then
    select points_par_euro into rate from public.fidelite_config where id = 1;
    pts := floor(greatest(coalesce(new.subtotal, new.total, 0) - coalesce(new.remise, 0), 0) * coalesce(rate, 1))::int;
    if pts > 0 then update public.profiles set points = points + pts where id = new.customer_id; end if;
    new.points_earned := pts; new.points_credited := true;
  end if;
  if new.status = 'annulee' and old.status is distinct from 'annulee' and new.customer_id is not null then
    if old.reward_points is not null and not old.reward_refunded then
      update public.profiles set points = points + old.reward_points where id = new.customer_id;
      delete from public.reward_redemptions where order_id = new.id::text;
      new.reward_refunded := true;
    end if;
    if old.points_credited and coalesce(old.points_earned, 0) > 0 then
      update public.profiles set points = greatest(0, points - old.points_earned) where id = new.customer_id;
      new.points_credited := false;
    end if;
  end if;
  return new;
end; $$;

-- ---------------------------------------------------------------------
-- 10 bis) Remise à la main sur une commande AVANT livraison / paiement (admin)
--   ex : 10 g à 100 € → tu fixes le total à 90 €. Remettre le total d'origine annule la remise.
-- ---------------------------------------------------------------------
create or replace function public.admin_remise_commande(p_order text, p_total numeric, p_motif text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare o record; brut numeric; r numeric;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  select * into o from public.orders where id::text = p_order for update;
  if o is null then raise exception 'ORDER_NOT_FOUND'; end if;
  if not ((coalesce(o.mode, 'local') = 'local' and coalesce(o.status, 'en_attente') in ('en_attente', 'en_cours', 'confirmee', 'en_livraison'))
          or (o.mode = 'france' and o.status = 'attente_paiement' and o.payment_status <> 'paid')) then
    raise exception 'REMISE_IMPOSSIBLE';
  end if;
  brut := coalesce(o.subtotal, o.total, 0) + coalesce(o.shipping_cost, 0);
  if o.subtotal is null then brut := coalesce(o.total, 0) + coalesce(o.remise, 0); end if;
  p_total := round(p_total, 2);
  if p_total is null or p_total <= 0 or p_total > brut then raise exception 'MONTANT_INVALIDE'; end if;
  r := brut - p_total;
  update public.orders
     set remise = r, remise_motif = case when r > 0 then nullif(btrim(coalesce(p_motif, '')), '') end, total = p_total,
         items = regexp_replace(coalesce(items, ''), ' — Total : .*$', '') || ' — Total : ' || replace(to_char(p_total, 'FM999990.00'), '.', ',') || '€'
                 || case when r > 0 then ' (remise -' || replace(to_char(r, 'FM999990.00'), '.', ',') || '€)' else '' end,
         updated_at = now()
   where id::text = p_order;
  select * into o from public.orders where id::text = p_order;
  return to_jsonb(o) || jsonb_build_object('id', p_order);
end; $$;
revoke all on function public.admin_remise_commande(text, numeric, text) from public, anon;
grant execute on function public.admin_remise_commande(text, numeric, text) to authenticated;

-- complete_order (bouton « Livrée ✓ » de l'admin) : passe par les mêmes règles
create or replace function public.complete_order(p_order text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  perform public.statut_commande_srv(p_order, 'terminee', '{}'::jsonb);
end; $$;
grant execute on function public.complete_order(text) to authenticated;

-- Fonctions internes : jamais appelables depuis le site
revoke all on function public.facture_prochain_rang(int) from public, anon, authenticated;

select 'Boutique prête (promos + remises)' as statut,
       (select actif from public.expedition_config where id = 1) as expedition_active,
       (select count(*) from public.menu_produits where prix_paliers is not null) as produits_avec_prix;
