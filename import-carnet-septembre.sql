-- =====================================================================
--  Smok'house — import du carnet de ventes (01/09 au 27/09/2026)
--  122 ventes hors site · total 2210 €
--  Ne retire rien du stock. Protégé contre le double import.
--  À coller dans Supabase > SQL Editor > New query > Run.
-- =====================================================================

-- Nouveaux produits (réservés à l'admin, n'apparaissent pas sur le site)
insert into public.products (id, name, category, stock_grams, cost_per_gram, base_price, active)
values
  ('calibanana', 'Cali Banana', 'resine', 0,
     coalesce((select cost_per_gram from public.products where id = 'caliplate'), 0),
     coalesce((select base_price from public.products where id = 'caliplate'), 10), false),
  ('filtree4x50', '4x Filtrée 50%', 'resine', 0, 0, 0, true)
on conflict (id) do nothing;

do $$
begin
  if exists (select 1 from public.manual_sales where created_at = '2026-09-27 00:00:00+00') then
    raise notice 'Carnet déjà importé : rien à faire.';
    return;
  end if;

  insert into public.manual_sales (sale_date, amount, items_json, payment, note, cost_amount, stock_deducted, created_at)
  select v.d::date, v.amt, v.items, v.pay, v.note, public.items_cost(v.items), false, '2026-09-27 00:00:00+00'
  from (values
  ('2026-09-01', 20, '{"caliplate": 2.05}'::jsonb, 'carte', null),
  ('2026-09-01', 20, '{"calibanana": 2.3}'::jsonb, 'carte', null),
  ('2026-09-01', 10, '{"caliplate": 1.09}'::jsonb, 'virement', null),
  ('2026-09-01', 20, '{"piatella": 2.2}'::jsonb, 'virement', null),
  ('2026-09-01', 20, '{"caliplate": 2.3}'::jsonb, 'especes', null),
  ('2026-09-01', 20, '{"ogkush": 3}'::jsonb, 'especes', '+30 %'),
  ('2026-09-07', 15, '{"caliplate": 1.51}'::jsonb, 'especes', null),
  ('2026-09-07', 15, '{"superlemonhaze": 2.11}'::jsonb, 'especes', null),
  ('2026-09-07', 10, '{"caliplate": 1.3}'::jsonb, 'credit', null),
  ('2026-09-07', 10, '{"ogkush": 1.2}'::jsonb, 'credit', null),
  ('2026-09-07', 10, '{"piatella": 1.2}'::jsonb, 'credit', null),
  ('2026-09-07', 10, '{"ogkush": 1.5}'::jsonb, 'especes', null),
  ('2026-09-07', 10, '{"caliplate": 1.2}'::jsonb, 'especes', null),
  ('2026-09-07', 30, '{"caliplate": 3.3}'::jsonb, 'especes', null),
  ('2026-09-08', 10, '{"caliplate": 1.1}'::jsonb, 'credit', null),
  ('2026-09-08', 10, '{"calibanana": 1.0}'::jsonb, 'credit', null),
  ('2026-09-08', 0, '{"manali": 2.34}'::jsonb, 'credit', 'Offert'),
  ('2026-09-08', 20, '{"caliplate": 2.1}'::jsonb, 'especes', null),
  ('2026-09-08', 20, '{"ogkush": 2.3}'::jsonb, 'especes', null),
  ('2026-09-08', 10, '{"caliplate": 1.13}'::jsonb, 'credit', null),
  ('2026-09-08', 10, '{"piatella": 1.23}'::jsonb, 'credit', null),
  ('2026-09-08', 10, '{"ogkush": 1.29}'::jsonb, 'credit', null),
  ('2026-09-09', 10, '{"caligazberry": 1.2}'::jsonb, 'credit', null),
  ('2026-09-09', 10, '{"ogkush": 1.16}'::jsonb, 'credit', null),
  ('2026-09-09', 10, '{"piatella": 1.3}'::jsonb, 'credit', null),
  ('2026-09-10', 30, '{"caliplate": 5.0}'::jsonb, 'especes', 'Récompense 100 pts'),
  ('2026-09-10', 20, '{"caligazberry": 2.1, "ogkush": 2}'::jsonb, 'especes', '+2 g OG offerts (150 pts)'),
  ('2026-09-10', 10, '{"caligazberry": 1.0}'::jsonb, 'autre', null),
  ('2026-09-10', 10, '{"ogkush": 1.1}'::jsonb, 'autre', null),
  ('2026-09-10', 10, '{"piatella": 1.1}'::jsonb, 'autre', null),
  ('2026-09-11', 35, '{"caligazberry": 4.0}'::jsonb, 'especes', null),
  ('2026-09-11', 35, '{"caligazberry": 4.0}'::jsonb, 'credit', null),
  ('2026-09-11', 10, '{"caliplate": 1.1}'::jsonb, 'credit', null),
  ('2026-09-11', 10, '{"calibanana": 1.0}'::jsonb, 'credit', null),
  ('2026-09-11', 20, '{"caliplate": 2.0}'::jsonb, 'especes', null),
  ('2026-09-12', 10, '{"superlemonhaze": 1.46}'::jsonb, 'especes', null),
  ('2026-09-12', 10, '{"ogkush": 1.28}'::jsonb, 'credit', null),
  ('2026-09-12', 10, '{"piatella": 1.3}'::jsonb, 'credit', null),
  ('2026-09-12', 10, '{"caliplate": 1.1}'::jsonb, 'credit', null),
  ('2026-09-13', 40, '{"bananadry": 4.7}'::jsonb, 'especes', null),
  ('2026-09-13', 10, '{"ogkush": 1.44}'::jsonb, 'autre', null),
  ('2026-09-13', 20, '{"caliplate": 2.05}'::jsonb, 'credit', null),
  ('2026-09-13', 10, '{"ogkush": 1.27}'::jsonb, 'credit', null),
  ('2026-09-13', 20, '{"caligazberry": 2.1, "ogkush": 2.15}'::jsonb, 'especes', '+2,15 g OG offerts (points)'),
  ('2026-09-13', 20, '{"ogkush": 2.21}'::jsonb, 'especes', null),
  ('2026-09-13', 20, '{"caliplate": 2.2}'::jsonb, 'especes', null),
  ('2026-09-14', 20, '{"caliplate": 2.0}'::jsonb, 'credit', null),
  ('2026-09-14', 10, '{"ogkush": 1.3}'::jsonb, 'credit', null),
  ('2026-09-14', 20, '{"ogkush": 2.43}'::jsonb, 'especes', null),
  ('2026-09-14', 30, '{"caliplate": 3.3}'::jsonb, 'especes', null),
  ('2026-09-15', 20, '{"caliplate": 2.3}'::jsonb, 'especes', '+20 %'),
  ('2026-09-15', 20, '{"superlemonhaze": 2.9}'::jsonb, 'especes', '+20 %'),
  ('2026-09-15', 20, '{"caliplate": 2.1}'::jsonb, 'especes', null),
  ('2026-09-15', 20, '{"caliplate": 5}'::jsonb, 'virement', '+3 g (150 pts)'),
  ('2026-09-15', 40, '{"caliplate": 4.0}'::jsonb, 'credit', null),
  ('2026-09-15', 10, '{"caliplate": 1.1}'::jsonb, 'autre', null),
  ('2026-09-15', 10, '{"caligazberry": 1.0}'::jsonb, 'autre', null),
  ('2026-09-16', 20, '{"caliplate": 2.06}'::jsonb, 'credit', null),
  ('2026-09-16', 10, '{"superlemonhaze": 1.4}'::jsonb, 'credit', null),
  ('2026-09-16', 30, '{"piatella": 3.51}'::jsonb, 'credit', null),
  ('2026-09-16', 30, '{"bananadry": 3.6}'::jsonb, 'autre', null),
  ('2026-09-17', 50, '{"bananadry": 6.3}'::jsonb, 'autre', null),
  ('2026-09-17', 20, '{"caliplate": 2.1}'::jsonb, 'especes', null),
  ('2026-09-17', 20, '{"caliplate": 2.0}'::jsonb, 'autre', null),
  ('2026-09-17', 10, '{"ogkush": 1.5}'::jsonb, 'autre', null),
  ('2026-09-17', 20, '{"piatella": 2.3}'::jsonb, 'credit', null),
  ('2026-09-17', 10, '{"caligazberry": 1.1, "caliplate": 0.5}'::jsonb, 'credit', '+0,5 g Cali Plate échantillon'),
  ('2026-09-18', 20, '{"ogkush": 2.2}'::jsonb, 'especes', null),
  ('2026-09-18', 20, '{"caliplate": 2.2}'::jsonb, 'credit', null),
  ('2026-09-18', 10, '{"ogkush": 1.4}'::jsonb, 'credit', null),
  ('2026-09-18', 20, '{"caliplate": 2.01}'::jsonb, 'autre', null),
  ('2026-09-18', 20, '{"caliplate": 2.03}'::jsonb, 'autre', null),
  ('2026-09-18', 10, '{"ogkush": 1.24}'::jsonb, 'autre', null),
  ('2026-09-18', 10, '{"caliplate": 2.07}'::jsonb, 'especes', '+1 g offert'),
  ('2026-09-19', 20, '{"caliplate": 2.07}'::jsonb, 'autre', null),
  ('2026-09-19', 10, '{"ogkush": 1.29}'::jsonb, 'autre', null),
  ('2026-09-19', 20, '{"ogkush": 2.4}'::jsonb, 'autre', null),
  ('2026-09-19', 20, '{"caliplate": 2.08}'::jsonb, 'especes', 'Leone'),
  ('2026-09-19', 20, '{"caliplate": 2.1}'::jsonb, 'credit', 'Kevin'),
  ('2026-09-19', 10, '{"caligazberry": 1.07}'::jsonb, 'credit', 'Kevin'),
  ('2026-09-20', 20, '{"caliplate": 2.07}'::jsonb, 'autre', null),
  ('2026-09-20', 20, '{"superlemonhaze": 2.34}'::jsonb, 'autre', null),
  ('2026-09-20', 20, '{"superlemonhaze": 2.25}'::jsonb, 'autre', null),
  ('2026-09-20', 20, '{"caliplate": 2.05}'::jsonb, 'autre', null),
  ('2026-09-20', 20, '{"caliplate": 5}'::jsonb, 'especes', '+3 g (150 pts)'),
  ('2026-09-21', 20, '{"caliplate": 2.1}'::jsonb, 'credit', null),
  ('2026-09-21', 10, '{"ogkush": 1.4}'::jsonb, 'credit', null),
  ('2026-09-22', 20, '{"caliplate": 2.0}'::jsonb, 'credit', null),
  ('2026-09-22', 10, '{"superlemonhaze": 1.3}'::jsonb, 'credit', null),
  ('2026-09-22', 30, '{"filtree4x50": 4.1}'::jsonb, 'especes', null),
  ('2026-09-22', 10, '{"superlemonhaze": 1.5}'::jsonb, 'autre', 'Gassin'),
  ('2026-09-22', 30, '{"bananadry": 3.8}'::jsonb, 'autre', null),
  ('2026-09-23', 10, '{"caliplate": 1.05}'::jsonb, 'especes', null),
  ('2026-09-23', 10, '{"caliplate": 1.01}'::jsonb, 'credit', null),
  ('2026-09-23', 10, '{"ogkush": 1.24}'::jsonb, 'credit', null),
  ('2026-09-23', 15, '{"caliplate": 1.51}'::jsonb, 'autre', null),
  ('2026-09-23', 15, '{"superlemonhaze": 1.9}'::jsonb, 'autre', null),
  ('2026-09-23', 20, '{"caliplate": 2.05}'::jsonb, 'autre', null),
  ('2026-09-23', 20, '{"caliplate": 2.04}'::jsonb, 'autre', null),
  ('2026-09-24', 30, '{"caliplate": 3.1}'::jsonb, 'credit', null),
  ('2026-09-24', 20, '{"caliplate": 2.1}'::jsonb, 'especes', null),
  ('2026-09-24', 20, '{"caliplate": 2.07}'::jsonb, 'especes', null),
  ('2026-09-24', 10, '{"caliplate": 1.13}'::jsonb, 'credit', null),
  ('2026-09-25', 20, '{"caliplate": 2.08}'::jsonb, 'autre', null),
  ('2026-09-25', 20, '{"caliplate": 2.2}'::jsonb, 'autre', null),
  ('2026-09-25', 10, '{"ogkush": 1.2}'::jsonb, 'autre', null),
  ('2026-09-25', 10, '{"superlemonhaze": 1.3}'::jsonb, 'autre', null),
  ('2026-09-25', 10, '{"bananadry": 1.21}'::jsonb, 'autre', null),
  ('2026-09-25', 50, '{"bananadry": 4.98}'::jsonb, 'autre', null),
  ('2026-09-26', 20, '{"filtree4x50": 2.45}'::jsonb, 'autre', null),
  ('2026-09-26', 20, '{"ogkush": 2.39}'::jsonb, 'autre', null),
  ('2026-09-26', 10, '{"piatella": 1.6}'::jsonb, 'autre', null),
  ('2026-09-26', 10, '{"ogkush": 1.27}'::jsonb, 'autre', null),
  ('2026-09-26', 20, '{"superlemonhaze": 2.3}'::jsonb, 'autre', null),
  ('2026-09-26', 70, '{"piatella": 10}'::jsonb, 'autre', null),
  ('2026-09-26', 10, '{"piatella": 1.4}'::jsonb, 'autre', null),
  ('2026-09-26', 10, '{"bananadry": 1.3}'::jsonb, 'autre', null),
  ('2026-09-26', 70, '{"bananadry": 9.5}'::jsonb, 'autre', null),
  ('2026-09-26', 10, '{"ogkush": 1.35}'::jsonb, 'autre', null),
  ('2026-09-26', 30, '{"filtree4x50": 3.8}'::jsonb, 'autre', null),
  ('2026-09-26', 20, '{"caligazberry": 2.3}'::jsonb, 'autre', null),
  ('2026-09-27', 20, '{"superlemonhaze": 2.5}'::jsonb, 'autre', null)
  ) as v(d, amt, items, pay, note);
end $$;

-- Vérification : chiffre d'affaires par jour
select sale_date as jour, count(*) as ventes, sum(amount) as ca
from public.manual_sales
where created_at = '2026-09-27 00:00:00+00'
group by sale_date order by sale_date;
