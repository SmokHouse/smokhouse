-- =====================================================================
--  Smok'house — brouillons de factures
--  Un brouillon reste modifiable et supprimable. Le numéro SH-AAAA-NNNN
--  n'est attribué qu'à la validation (la facture devient alors définitive).
--  À coller dans Supabase > SQL Editor > New query > Run (après factures-setup.sql).
-- =====================================================================

create table if not exists public.factures_brouillons (
  id            bigserial primary key,
  source        text not null check (source in ('commande', 'vente_manuelle', 'libre')),
  source_ref    text,
  client        jsonb not null default '{}'::jsonb,
  lignes        jsonb not null default '[]'::jsonb,
  date_vente    date,
  mode_paiement text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index if not exists factures_brouillons_source_uniq
  on public.factures_brouillons (source, source_ref) where source_ref is not null;

alter table public.factures_brouillons enable row level security;
grant select, insert, update, delete on public.factures_brouillons to authenticated;
grant usage, select on sequence public.factures_brouillons_id_seq to authenticated;
drop policy if exists brouillons_admin_all on public.factures_brouillons;
create policy brouillons_admin_all on public.factures_brouillons
  for all using (public.is_admin()) with check (public.is_admin());

-- Valider un brouillon : émet la facture définitive (numéro attribué) puis supprime le brouillon.
-- Tout se fait dans la même transaction : si l'émission échoue, le brouillon reste et aucun numéro n'est consommé.
create or replace function public.valider_brouillon(p_id bigint)
returns table (id bigint, numero text)
language plpgsql security definer set search_path = public as $$
declare b record; r record;
begin
  if not public.is_admin() then raise exception 'NOT_ADMIN'; end if;
  select * into b from public.factures_brouillons fb where fb.id = p_id for update;
  if b is null then raise exception 'BROUILLON_INTROUVABLE'; end if;
  select * into r from public.emettre_facture(b.source, b.source_ref, b.client, b.lignes, b.date_vente, b.mode_paiement);
  delete from public.factures_brouillons fb where fb.id = p_id;
  return query select r.id, r.numero;
end; $$;
grant execute on function public.valider_brouillon(bigint) to authenticated;

select 'Brouillons prêts' as statut;
