-- =====================================================================
--  Smok'house — surnoms et notes privées sur les clients (visibles par l'admin seulement)
--  Stockés à part de la fiche client : le client ne peut jamais les lire.
--  À coller dans Supabase > SQL Editor > New query > Run. Ne supprime rien.
-- =====================================================================
create table if not exists public.client_notes (
  customer_id uuid primary key references public.profiles(id) on delete cascade,
  alias       text,          -- ex : « Kevin (Brives) »
  note        text,          -- ex : « Préfère la résine, livrer après 18h »
  updated_at  timestamptz not null default now()
);
alter table public.client_notes enable row level security;
grant select, insert, update, delete on public.client_notes to authenticated;
drop policy if exists client_notes_admin_all on public.client_notes;
create policy client_notes_admin_all on public.client_notes
  for all using (public.is_admin()) with check (public.is_admin());
select 'Notes clients prêtes' as statut;
