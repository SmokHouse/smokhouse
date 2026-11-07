-- =====================================================================
--  Smok'house — mise à jour Supabase pour l'app client + l'app admin
--  À coller UNE fois dans Supabase > SQL Editor > New query > Run.
--  Le script peut être relancé sans risque (il ne supprime aucune donnée).
-- =====================================================================

-- 1) Petite fonction utilitaire : l'utilisateur connecté est-il admin ?
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- 2) Nouvelles colonnes sur les commandes
alter table public.orders add column if not exists items_json jsonb;          -- {"ogkush": 3, "manali": 2}  (grammes)
alter table public.orders add column if not exists total numeric(10,2);       -- total TTC en €
alter table public.orders add column if not exists stock_deducted boolean not null default false;
alter table public.orders add column if not exists completed_at timestamptz;

-- 3) Produits + stock (réservé à l'admin : contient les prix d'achat)
create table if not exists public.products (
  id              text primary key,             -- même identifiant que sur le site (ogkush, manali...)
  name            text not null,
  category        text not null default 'fleur', -- 'fleur' ou 'resine'
  stock_grams     numeric(10,2) not null default 0,
  cost_per_gram   numeric(10,2) not null default 0, -- prix d'achat au gramme
  base_price      numeric(10,2) not null default 0, -- prix de vente au gramme (1er palier)
  low_stock_alert numeric(10,2) not null default 20,
  active          boolean not null default true,
  updated_at      timestamptz not null default now()
);

insert into public.products (id, name, category, base_price) values
  ('superlemonhaze','SuperLemon Haze','fleur',9),
  ('ogkush','OG Kush','fleur',9),
  ('piatella','Piatella','resine',9),
  ('bananadry','Banana Dry','resine',9),
  ('caliplate','Cali Plate','resine',10),
  ('manali','Manali','resine',10),
  ('caligazberry','CaliGaz Berry','resine',10)
on conflict (id) do nothing;

-- 4) Historique des mouvements de stock
create table if not exists public.stock_movements (
  id          bigserial primary key,
  product_id  text not null references public.products(id) on delete cascade,
  delta_grams numeric(10,2) not null,            -- + réassort / - vente ou perte
  reason      text not null,                     -- 'reassort', 'vente', 'ajustement', 'perte'
  order_id    text,
  unit_cost   numeric(10,2),
  created_at  timestamptz not null default now()
);

-- 5) Sécurité (RLS) : seul l'admin voit et modifie le stock
alter table public.products enable row level security;
alter table public.stock_movements enable row level security;

drop policy if exists products_admin_all on public.products;
create policy products_admin_all on public.products
  for all using (public.is_admin()) with check (public.is_admin());

drop policy if exists stock_movements_admin_all on public.stock_movements;
create policy stock_movements_admin_all on public.stock_movements
  for all using (public.is_admin()) with check (public.is_admin());

-- L'admin doit pouvoir lire/modifier toutes les commandes et voir tous les clients
drop policy if exists orders_admin_select on public.orders;
create policy orders_admin_select on public.orders for select using (public.is_admin());
drop policy if exists orders_admin_update on public.orders;
create policy orders_admin_update on public.orders for update using (public.is_admin());
drop policy if exists profiles_admin_select on public.profiles;
create policy profiles_admin_select on public.profiles for select using (public.is_admin());

-- 6) Disponibilité publique (le site affiche "Rupture" sans révéler les prix d'achat)
create or replace function public.public_stock()
returns table (id text, available boolean)
language sql stable security definer set search_path = public
as $$
  select p.id, (p.active and p.stock_grams > 0) from public.products p;
$$;
grant execute on function public.public_stock() to anon, authenticated;

-- 7) Réassort / ajustement de stock (admin)
create or replace function public.adjust_stock(p_product text, p_delta numeric, p_reason text, p_unit_cost numeric default null)
returns numeric
language plpgsql security definer set search_path = public
as $$
declare new_stock numeric;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  update public.products
     set stock_grams = greatest(0, stock_grams + p_delta),
         cost_per_gram = coalesce(p_unit_cost, cost_per_gram),
         updated_at = now()
   where id = p_product
   returning stock_grams into new_stock;
  if new_stock is null then raise exception 'PRODUCT_NOT_FOUND'; end if;
  insert into public.stock_movements (product_id, delta_grams, reason, unit_cost)
  values (p_product, p_delta, p_reason, p_unit_cost);
  return new_stock;
end;
$$;
grant execute on function public.adjust_stock(text, numeric, text, numeric) to authenticated;

-- 8) Terminer une commande : passe en "terminee" et retire le stock (une seule fois)
create or replace function public.complete_order(p_order text)
returns void
language plpgsql security definer set search_path = public
as $$
declare o record; k text; g numeric;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  select * into o from public.orders where id::text = p_order for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;

  if not o.stock_deducted and o.items_json is not null then
    for k, g in select key, value::numeric from jsonb_each_text(o.items_json) loop
      update public.products set stock_grams = greatest(0, stock_grams - g), updated_at = now() where id = k;
      if found then
        insert into public.stock_movements (product_id, delta_grams, reason, order_id)
        values (k, -g, 'vente', p_order);
      end if;
    end loop;
  end if;

  update public.orders
     set status = 'terminee', stock_deducted = true, completed_at = now()
   where id::text = p_order;
end;
$$;
grant execute on function public.complete_order(text) to authenticated;

-- 9) Temps réel : l'app admin reçoit les nouvelles commandes instantanément,
--    le client voit le statut de sa commande changer en direct.
do $$
begin
  alter publication supabase_realtime add table public.orders;
exception when duplicate_object then null;
end $$;
