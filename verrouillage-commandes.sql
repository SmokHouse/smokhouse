-- =====================================================================
--  Smok'house — VERROUILLAGE des commandes (à lancer EN DERNIER)
--  ⚠️ Seulement APRÈS avoir mis en ligne la nouvelle version du site (GitHub + Netlify)
--     et vérifié qu'une commande test passe bien.
--  Effet : plus personne ne peut créer une commande directement depuis le navigateur.
--  Toutes les commandes passent par la Netlify Function « create-order », qui recalcule
--  prix, port, total et vérifie le stock. Ne supprime aucune donnée.
-- =====================================================================

-- Supprime toutes les règles qui autorisent l'insertion directe dans « orders »
do $$
declare p record;
begin
  for p in select policyname from pg_policies
            where schemaname = 'public' and tablename = 'orders' and cmd in ('INSERT', 'ALL')
  loop
    execute format('drop policy %I on public.orders', p.policyname);
  end loop;
end $$;

-- Les clients ne peuvent plus ni créer ni modifier ni supprimer une commande eux-mêmes
revoke insert, delete on public.orders from anon, authenticated;
revoke update on public.orders from anon;

-- L'admin garde la lecture et la modification (app admin)
drop policy if exists orders_admin_select on public.orders;
create policy orders_admin_select on public.orders for select using (public.is_admin());
drop policy if exists orders_admin_update on public.orders;
create policy orders_admin_update on public.orders for update using (public.is_admin()) with check (public.is_admin());

-- L'ancienne fonction « appliquer une récompense depuis le navigateur » n'est plus utilisée
revoke execute on function public.appliquer_recompense_commande(text, int) from anon, authenticated;

-- Vérification : il ne doit rester aucune ligne « INSERT »
select policyname, cmd from pg_policies where schemaname = 'public' and tablename = 'orders' order by cmd;
