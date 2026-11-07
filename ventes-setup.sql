-- =====================================================================
--  Smok'house — ventes hors site + prix d'achat (marge)
--  À coller UNE fois dans Supabase > SQL Editor > New query > Run.
--  Ne supprime aucune donnée existante. Peut être relancé sans risque.
-- =====================================================================

-- 1) Coût d'achat figé au moment de la vente (pour une marge juste dans le temps)
alter table public.orders add column if not exists cost_total numeric(10,2);

-- 2) Ventes hors site (boutique, main propre, Snap, Insta...)
create table if not exists public.manual_sales (
  id             bigserial primary key,
  sale_date      date not null default current_date,
  amount         numeric(10,2) not null default 0,   -- montant encaissé
  cost_amount    numeric(10,2),                      -- coût d'achat (null = inconnu)
  items_json     jsonb,                              -- {"ogkush": 3} en grammes (optionnel)
  payment        text not null default 'especes',    -- especes / carte / virement / autre
  note           text,
  stock_deducted boolean not null default false,
  created_at     timestamptz not null default now()
);

alter table public.manual_sales enable row level security;
grant select, insert, update, delete on public.manual_sales to authenticated;
grant usage, select on sequence public.manual_sales_id_seq to authenticated;
drop policy if exists manual_sales_admin_all on public.manual_sales;
create policy manual_sales_admin_all on public.manual_sales
  for all using (public.is_admin()) with check (public.is_admin());

-- 3) Coût d'achat d'un panier {"produit": grammes} (null si un prix d'achat manque)
create or replace function public.items_cost(p_items jsonb)
returns numeric
language plpgsql stable security definer set search_path = public
as $$
declare k text; g numeric; c numeric; total numeric := 0;
begin
  if p_items is null or p_items = '{}'::jsonb then return null; end if;
  for k, g in select key, value::numeric from jsonb_each_text(p_items) loop
    select cost_per_gram into c from public.products where id = k;
    if c is null or c <= 0 then return null; end if;
    total := total + c * g;
  end loop;
  return round(total, 2);
end;
$$;

-- 4) Ajouter une vente hors site (retire le stock si demandé)
create or replace function public.add_manual_sale(
  p_date date, p_amount numeric, p_items jsonb, p_cost numeric,
  p_payment text, p_note text, p_deduct boolean)
returns bigint
language plpgsql security definer set search_path = public
as $$
declare new_id bigint; k text; g numeric;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  if p_items = '{}'::jsonb then p_items := null; end if;

  insert into public.manual_sales (sale_date, amount, cost_amount, items_json, payment, note, stock_deducted)
  values (coalesce(p_date, current_date), coalesce(p_amount, 0),
          coalesce(p_cost, public.items_cost(p_items)), p_items,
          coalesce(nullif(p_payment, ''), 'especes'), nullif(p_note, ''),
          coalesce(p_deduct, false) and p_items is not null)
  returning id into new_id;

  if coalesce(p_deduct, false) and p_items is not null then
    for k, g in select key, value::numeric from jsonb_each_text(p_items) loop
      update public.products set stock_grams = greatest(0, stock_grams - g), updated_at = now() where id = k;
      if found then
        insert into public.stock_movements (product_id, delta_grams, reason, order_id)
        values (k, -g, 'vente', 'M-' || new_id);
      end if;
    end loop;
  end if;
  return new_id;
end;
$$;
grant execute on function public.add_manual_sale(date, numeric, jsonb, numeric, text, text, boolean) to authenticated;

-- 5) Supprimer une vente hors site (remet le stock si elle l'avait retiré)
create or replace function public.delete_manual_sale(p_id bigint)
returns void
language plpgsql security definer set search_path = public
as $$
declare s record; k text; g numeric;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  select * into s from public.manual_sales where id = p_id for update;
  if not found then return; end if;
  if s.stock_deducted and s.items_json is not null then
    for k, g in select key, value::numeric from jsonb_each_text(s.items_json) loop
      update public.products set stock_grams = stock_grams + g, updated_at = now() where id = k;
      if found then
        insert into public.stock_movements (product_id, delta_grams, reason, order_id)
        values (k, g, 'annulation', 'M-' || p_id);
      end if;
    end loop;
  end if;
  delete from public.manual_sales where id = p_id;
end;
$$;
grant execute on function public.delete_manual_sale(bigint) to authenticated;

-- 6) Terminer une commande du site : fige aussi son coût d'achat
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
     set status = 'terminee', stock_deducted = true, completed_at = coalesce(completed_at, now()),
         cost_total = coalesce(cost_total, public.items_cost(items_json))
   where id::text = p_order;
end;
$$;
grant execute on function public.complete_order(text) to authenticated;
