-- =====================================================================
--  Smok'house — STUDIO IA (création d'images depuis l'app admin)
--  Garde l'historique des images créées (admin seulement).
--  À lancer APRÈS photos-setup.sql. Ne supprime rien. Peut être relancé.
-- =====================================================================
create table if not exists public.ia_images (
  id         uuid primary key default gen_random_uuid(),
  product_id text,                    -- variété concernée (ou vide pour une image libre)
  prompt     text not null,           -- ce que tu as demandé
  style      text not null default 'smokhouse',
  format     text not null default 'paysage' check (format in ('paysage', 'carre', 'portrait')),
  qualite    text not null default 'medium' check (qualite in ('low', 'medium', 'high')),
  ref_url    text,                    -- ta photo de départ (optionnel)
  status     text not null default 'pending' check (status in ('pending', 'done', 'error')),
  url        text,                    -- image créée
  erreur     text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ia_images_created_idx on public.ia_images (created_at desc);
alter table public.ia_images enable row level security;
grant select, insert, update, delete on public.ia_images to authenticated;
drop policy if exists ia_images_admin on public.ia_images;
create policy ia_images_admin on public.ia_images for all using (public.is_admin()) with check (public.is_admin());

select 'Studio IA prêt' as statut;
