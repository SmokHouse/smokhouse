-- =====================================================================
--  Smok'house — correctif de sécurité (fiches clients)
--  Empêche un client de modifier lui-même ses points, son statut admin
--  ou son numéro de carte. Ne supprime et ne modifie aucune donnée.
--  À coller dans Supabase > SQL Editor > New query > Run.
-- =====================================================================

create or replace function public.protect_profile_fields()
returns trigger
language plpgsql set search_path = public  -- surtout PAS security definer : on doit voir qui appelle vraiment
as $$
begin
  -- Les fonctions officielles (ajout de points, récompenses...) tournent avec
  -- les droits du propriétaire : elles restent autorisées. L'admin aussi.
  if current_user not in ('authenticated', 'anon') or public.is_admin() then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Création de compte depuis le site : on part toujours de zéro
    new.points   := 0;
    new.is_admin := false;
    new.member_number := 'SH-' || lpad((floor(random() * 900000) + 100000)::int::text, 6, '0');
  else
    -- Mise à jour par le client : il ne peut changer que son nom et son panier
    new.points        := old.points;
    new.is_admin      := old.is_admin;
    new.member_number := old.member_number;
    new.id            := old.id;
  end if;
  return new;
end;
$$;

drop trigger if exists protect_profile_fields on public.profiles;
create trigger protect_profile_fields
  before insert or update on public.profiles
  for each row execute function public.protect_profile_fields();

-- Les fonctions de points doivent tourner avec les droits du propriétaire
-- (sinon la protection ci-dessus bloquerait aussi la déduction des points)
do $$
declare f record;
begin
  for f in select oid::regprocedure as sig from pg_proc
           where pronamespace = 'public'::regnamespace
             and proname in ('redeem_reward','add_points_by_member','remove_points_by_member')
  loop
    execute format('alter function %s security definer', f.sig);
  end loop;
end $$;

-- Vérification : qui est admin aujourd'hui ? (tu dois être le seul)
select name, email, member_number, points from public.profiles where is_admin = true;
