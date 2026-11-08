-- =====================================================================
--  Smok'house — PHOTOS des variétés (envoyées depuis l'app admin)
--  Crée un espace de stockage « produits » : les photos sont publiques (visibles sur le site),
--  mais seul ton compte admin peut en ajouter, remplacer ou supprimer.
--  À coller dans Supabase > SQL Editor > New query > Run. Ne supprime rien.
-- =====================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('produits', 'produits', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

drop policy if exists "produits lecture publique" on storage.objects;
create policy "produits lecture publique" on storage.objects
  for select using (bucket_id = 'produits');

drop policy if exists "produits ajout admin" on storage.objects;
create policy "produits ajout admin" on storage.objects
  for insert to authenticated with check (bucket_id = 'produits' and public.is_admin());

drop policy if exists "produits modif admin" on storage.objects;
create policy "produits modif admin" on storage.objects
  for update to authenticated using (bucket_id = 'produits' and public.is_admin()) with check (bucket_id = 'produits' and public.is_admin());

drop policy if exists "produits suppression admin" on storage.objects;
create policy "produits suppression admin" on storage.objects
  for delete to authenticated using (bucket_id = 'produits' and public.is_admin());

select 'Photos prêtes' as statut, (select public from storage.buckets where id = 'produits') as public;
