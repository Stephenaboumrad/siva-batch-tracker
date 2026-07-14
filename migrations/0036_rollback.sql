-- ============================================================
-- Rollback 0036 - re-creation de la FK pos_transactions.vendeur_id
--                 vers employes(employe_id) (etat 0002)
-- ------------------------------------------------------------
-- ATTENTION : ce rollback re-bloque les ventes caisse tant que les
-- vendeur_id ne correspondent pas a des employes.employe_id (la panne
-- que 0036 corrige). Ne l'executer que si la strategie change.
--
-- PRE-CHECK OBLIGATOIRE (lecture seule) : la contrainte ne peut etre
-- re-creee que si AUCUNE ligne orpheline n'existe. Attendu : 0 ligne.
--   select distinct t.vendeur_id
--     from pos_transactions t
--    where t.vendeur_id is not null
--      and not exists (
--        select 1 from employes e where e.employe_id = t.vendeur_id
--      );
-- Si des lignes sortent : corriger les donnees d'abord (mettre les
-- vendeur_id orphelins a null, ou creer les lignes employes voulues),
-- sinon le ADD CONSTRAINT ci-dessous echoue en bloc.
--
-- Idempotent : to_regclass sur les deux tables + pg_constraint avant
-- creation. ASCII uniquement, pas de commentaire en fin de ligne
-- d'instruction.
-- ============================================================

do $$
begin
  if to_regclass('public.pos_transactions') is null then
    raise notice '0036_rollback: table pos_transactions absente - ignore.';
    return;
  end if;

  if to_regclass('public.employes') is null then
    raise notice '0036_rollback: table employes absente - FK impossible, ignore.';
    return;
  end if;

  if exists (
    select 1
      from pg_constraint con
      join pg_attribute att
        on att.attrelid = con.conrelid
       and att.attnum = any (con.conkey)
     where con.conrelid = 'public.pos_transactions'::regclass
       and con.contype = 'f'
       and att.attname = 'vendeur_id'
  ) then
    raise notice '0036_rollback: une FK existe deja sur vendeur_id - ignore.';
    return;
  end if;

  alter table public.pos_transactions
    add constraint pos_transactions_vendeur_id_fkey
    foreign key (vendeur_id) references public.employes(employe_id)
    on delete set null;
  raise notice '0036_rollback: contrainte pos_transactions_vendeur_id_fkey re-creee.';
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- La FK est de retour (attendu : 1 ligne) :
--   select con.conname
--     from pg_constraint con
--     join pg_attribute att
--       on att.attrelid = con.conrelid
--      and att.attnum = any (con.conkey)
--    where con.conrelid = 'public.pos_transactions'::regclass
--      and con.contype = 'f'
--      and att.attname = 'vendeur_id';
-- ============================================================
