-- =====================================================================
--  Smok'house — montant minimum d'achat pour utiliser une récompense
--  100 pts : dès 20 € d'achat · 150 pts : dès 30 € d'achat
--  À coller dans Supabase > SQL Editor > New query > Run (après fidelite-commandes-setup.sql).
-- =====================================================================
alter table public.fidelite_recompenses add column if not exists min_achat numeric(10,2) not null default 0;
update public.fidelite_recompenses set min_achat = 20 where points = 100;
update public.fidelite_recompenses set min_achat = 30 where points = 150;

create or replace function public.fidelite_public()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'points_par_euro', (select points_par_euro from public.fidelite_config where id = 1),
    'recompenses', coalesce((select jsonb_agg(jsonb_build_object('points', points, 'label', label, 'min_achat', min_achat) order by points)
                             from public.fidelite_recompenses where active), '[]'::jsonb));
$$;
grant execute on function public.fidelite_public() to anon, authenticated;

-- Même fonction qu'avant + contrôle du minimum d'achat (vérifié côté serveur, impossible à contourner)
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
  if coalesce(o.total, 0) < r.min_achat then raise exception 'MIN_ACHAT'; end if;

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

select points, label, min_achat from public.fidelite_recompenses where active order by points;
