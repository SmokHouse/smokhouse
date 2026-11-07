-- =====================================================================
--  Smok'house — bonus « ticket à gratter » (+10 %, +20 %, +30 %…) sur les commandes du site
--  Garde le détail des grammes offerts sur la commande. Ne supprime rien.
--  À coller dans Supabase > SQL Editor > New query > Run.
-- =====================================================================
alter table public.orders add column if not exists offert_json jsonb;   -- {"caliplate": 0.4} grammes offerts (inclus dans items_json pour le stock)
alter table public.orders add column if not exists bonus_pct int;       -- % du ticket à gratter
select 'Bonus ticket prêt' as statut;
