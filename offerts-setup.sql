-- =====================================================================
--  Smok'house — produits offerts et points fidélité sur les ventes hors site
--  À coller dans Supabase > SQL Editor > New query > Run. Ne supprime rien.
-- =====================================================================
alter table public.manual_sales add column if not exists offert_json     jsonb;  -- {"ogkush": 3} grammes offerts (déjà inclus dans items_json pour le stock et le coût)
alter table public.manual_sales add column if not exists points_utilises int;    -- points fidélité utilisés pour ce cadeau
select 'Offerts prêts' as statut;
