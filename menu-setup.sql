-- =====================================================================
--  Smok'house — page « menu coffee shop » (version test : /menu.html)
--  Infos affichées sur le menu (profil, taux, arômes, photo, badges) + « menu du jour ».
--  Lecture publique (c'est un menu), modification réservée à l'admin.
--  Ne contient AUCUN prix d'achat. Ne supprime aucune donnée.
--  À coller dans Supabase > SQL Editor > New query > Run.
-- =====================================================================

create table if not exists public.menu_produits (
  product_id text primary key,
  nom        text not null,
  categorie  text not null default 'fleur' check (categorie in ('fleur', 'resine')),
  profil     text check (profil in ('indica', 'sativa', 'hybride')),
  taux       text,                 -- ex : « THV 40 % » ou « CBD 15 % »
  aromes     text,                 -- ex : « fruité, citronné, sucré »
  photo_url  text,                 -- vide = /menu/<id>.jpg puis illustration
  nouveau    boolean not null default false,
  top_vente  boolean not null default false,   -- forcé à la main (sinon calculé sur 30 jours)
  visible    boolean not null default true,
  prix_1g    numeric(10,2),        -- uniquement pour une variété absente du site (prix au gramme)
  ordre      int not null default 100,
  updated_at timestamptz not null default now()
);
insert into public.menu_produits (product_id, nom, categorie, taux, ordre) values
  ('superlemonhaze', 'SuperLemon Haze', 'fleur',  'THV 40 %', 10),
  ('ogkush',         'OG Kush',         'fleur',  'THV 40 %', 20),
  ('piatella',       'Piatella',        'resine', 'THV 60 %', 30),
  ('caliplate',      'Cali Plate',      'resine', 'THV 80 %', 40),
  ('caligazberry',   'CaliGaz Berry',   'resine', 'THV 80 %', 50),
  ('manali',         'Manali',          'resine', 'THV 80 %', 60),
  ('bananadry',      'Banana Dry',      'resine', 'THV 50 %', 70)
on conflict (product_id) do nothing;

create table if not exists public.menu_jour (
  id         int primary key default 1 check (id = 1),
  actif      boolean not null default true,
  titre      text not null default 'Le menu du jour',
  texte      text,
  product_id text,                 -- variété mise en avant
  promo      text,                 -- ex : « -10 % sur la Piatella jusqu'à dimanche »
  updated_at timestamptz not null default now()
);
insert into public.menu_jour (id, texte, product_id)
values (1, 'Notre coup de cœur du moment, à goûter au comptoir.', 'caliplate')
on conflict (id) do nothing;

alter table public.menu_produits enable row level security;
alter table public.menu_jour enable row level security;
grant select on public.menu_produits, public.menu_jour to anon, authenticated;
grant insert, update, delete on public.menu_produits, public.menu_jour to authenticated;

drop policy if exists menu_produits_lecture on public.menu_produits;
create policy menu_produits_lecture on public.menu_produits for select using (true);
drop policy if exists menu_produits_admin on public.menu_produits;
create policy menu_produits_admin on public.menu_produits for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists menu_jour_lecture on public.menu_jour;
create policy menu_jour_lecture on public.menu_jour for select using (true);
drop policy if exists menu_jour_admin on public.menu_jour;
create policy menu_jour_admin on public.menu_jour for all using (public.is_admin()) with check (public.is_admin());

-- « Top vente » automatique : les 2 variétés les plus vendues (en grammes) sur 30 jours,
-- site + ventes hors site. Ne renvoie que des identifiants de produits, aucun chiffre.
create or replace function public.top_ventes()
returns setof text
language plpgsql stable security definer set search_path = public as $$
declare r record; t jsonb := '{}'::jsonb;
begin
  begin
    for r in select key, sum(value::numeric) as g from public.orders o, jsonb_each_text(o.items_json)
              where o.status = 'terminee' and o.items_json is not null
                and coalesce(o.completed_at, o.created_at) > now() - interval '30 days'
              group by key loop
      t := t || jsonb_build_object(r.key, coalesce((t->>r.key)::numeric, 0) + r.g);
    end loop;
  exception when undefined_table or undefined_column then null;
  end;
  begin
    for r in select key, sum(value::numeric) as g from public.manual_sales s, jsonb_each_text(s.items_json)
              where s.items_json is not null and s.sale_date > current_date - 30
              group by key loop
      t := t || jsonb_build_object(r.key, coalesce((t->>r.key)::numeric, 0) + r.g);
    end loop;
  exception when undefined_table or undefined_column then null;
  end;
  return query select key from jsonb_each_text(t) order by value::numeric desc limit 2;
end; $$;
grant execute on function public.top_ventes() to anon, authenticated;

select 'Menu prêt' as statut, (select count(*) from public.menu_produits) as varietes;
