-- =====================================================================
--  Smok'house — points fidélité automatiques sur les commandes du site
--  • Points gagnés crédités automatiquement quand la commande passe « Livrée »
--  • Récompense choisie au moment de la commande : points retirés tout de suite
--  • Commande annulée : points de la récompense rendus, points gagnés retirés
--  À coller dans Supabase > SQL Editor > New query > Run. Ne supprime aucune donnée.
-- =====================================================================

-- 1) Réglages : points gagnés par euro + liste des récompenses
create table if not exists public.fidelite_config (
  id              int primary key default 1 check (id = 1),
  points_par_euro numeric(6,2) not null default 1,
  updated_at      timestamptz not null default now()
);
insert into public.fidelite_config (id) values (1) on conflict (id) do nothing;

create table if not exists public.fidelite_recompenses (
  points int primary key check (points > 0),
  label  text not null,
  active boolean not null default true
);
insert into public.fidelite_recompenses (points, label) values
  (50,  'Accessoires offerts'),
  (100, '2g de fleur ou résine offerte'),
  (150, '4g de fleur ou 3g de résine offert')
on conflict (points) do nothing;

alter table public.fidelite_config enable row level security;
alter table public.fidelite_recompenses enable row level security;
grant select, insert, update, delete on public.fidelite_config, public.fidelite_recompenses to authenticated;
drop policy if exists fidelite_config_admin on public.fidelite_config;
create policy fidelite_config_admin on public.fidelite_config for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists fidelite_recompenses_admin on public.fidelite_recompenses;
create policy fidelite_recompenses_admin on public.fidelite_recompenses for all using (public.is_admin()) with check (public.is_admin());

-- Lecture publique (le site affiche les récompenses et les points à gagner)
create or replace function public.fidelite_public()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'points_par_euro', (select points_par_euro from public.fidelite_config where id = 1),
    'recompenses', coalesce((select jsonb_agg(jsonb_build_object('points', points, 'label', label) order by points)
                             from public.fidelite_recompenses where active), '[]'::jsonb));
$$;
grant execute on function public.fidelite_public() to anon, authenticated;

-- 2) Colonnes de suivi sur les commandes
alter table public.orders add column if not exists reward_points   int;
alter table public.orders add column if not exists reward_label    text;
alter table public.orders add column if not exists reward_refunded boolean not null default false;
alter table public.orders add column if not exists points_earned   int;
alter table public.orders add column if not exists points_credited boolean not null default false;
alter table public.reward_redemptions add column if not exists order_id text;

-- 3) Un client qui passe commande ne peut pas s'attribuer lui-même une récompense, des points ou un statut
create or replace function public.orders_protect_client_insert()
returns trigger language plpgsql set search_path = public as $$
begin
  if current_user in ('anon', 'authenticated') and not public.is_admin() then
    new.reward_points := null; new.reward_label := null; new.reward_refunded := false;
    new.points_earned := null; new.points_credited := false;
    new.status := 'en_attente'; new.stock_deducted := false; new.completed_at := null;
    if new.customer_id is not null and new.customer_id <> auth.uid() then new.customer_id := null; end if;
  end if;
  return new;
end; $$;
drop trigger if exists orders_protect_client_insert on public.orders;
create trigger orders_protect_client_insert before insert on public.orders
  for each row execute function public.orders_protect_client_insert();

-- 4) Le client choisit sa récompense sur SA commande en attente : points retirés tout de suite
create or replace function public.appliquer_recompense_commande(p_order text, p_points int)
returns int
language plpgsql security definer set search_path = public as $$
declare o record; r record; solde int;
begin
  if auth.uid() is null then raise exception 'NOT_LOGGED_IN'; end if;
  select * into o from public.orders where id::text = p_order for update;
  if o is null or o.customer_id is distinct from auth.uid() then raise exception 'ORDER_NOT_FOUND'; end if;
  if o.status <> 'en_attente' then raise exception 'ORDER_LOCKED'; end if;
  if o.reward_points is not null then raise exception 'ALREADY_REWARDED'; end if;
  select * into r from public.fidelite_recompenses where points = p_points and active;
  if r is null then raise exception 'REWARD_NOT_FOUND'; end if;

  update public.profiles set points = points - r.points
   where id = auth.uid() and points >= r.points
   returning points into solde;
  if solde is null then raise exception 'NOT_ENOUGH_POINTS'; end if;

  insert into public.reward_redemptions (customer_id, reward_label, points_used, order_id)
  values (auth.uid(), r.label || ' (commande site)', r.points, p_order);
  update public.orders set reward_points = r.points, reward_label = r.label where id::text = p_order;
  return solde;
end; $$;
grant execute on function public.appliquer_recompense_commande(text, int) to authenticated;

-- 5) Automatismes sur changement de statut
create or replace function public.orders_fidelite_statut()
returns trigger language plpgsql security definer set search_path = public as $$
declare rate numeric; pts int;
begin
  -- Livrée : on crédite les points gagnés (une seule fois)
  if new.status = 'terminee' and old.status is distinct from 'terminee'
     and new.customer_id is not null and not old.points_credited then
    select points_par_euro into rate from public.fidelite_config where id = 1;
    pts := floor(coalesce(new.total, 0) * coalesce(rate, 1))::int;
    if pts > 0 then
      update public.profiles set points = points + pts where id = new.customer_id;
    end if;
    new.points_earned := pts; new.points_credited := true;
  end if;

  -- Annulée : on rend la récompense et on retire les points éventuellement gagnés
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
drop trigger if exists orders_fidelite_statut on public.orders;
create trigger orders_fidelite_statut before update of status on public.orders
  for each row execute function public.orders_fidelite_statut();

select 'Fidélité commandes prête' as statut, (select points_par_euro from public.fidelite_config where id = 1) as points_par_euro;
