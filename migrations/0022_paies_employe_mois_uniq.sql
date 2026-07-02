-- ============================================================
-- Migration 0022 - Contrainte unique paies (employe_id, mois)
-- ------------------------------------------------------------
-- Restauration du module RH (audit A-F1) : generatePaieFor / generateAllPaies
-- inserent une fiche de paie par employe et par mois. Cote client, un double
-- clic est deja gate (bouton desactive + test STATE), mais rien cote serveur
-- n'empechait deux fiches identiques (double-tap sur reseau lent, deux
-- appareils, replay de la file hors ligne). Cette contrainte fait du serveur
-- la garantie finale : 1 fiche de paie max par (employe_id, mois).
--
-- Le front traite la violation comme une INFORMATION (toast "Paie deja
-- generee pour ce mois"), pas comme une erreur - detection sur le nom de
-- contrainte paies_employe_mois_uniq dans le message PostgREST.
--
-- STRICTEMENT ADDITIF : aucune colonne creee/supprimee/renommee. mois est
-- nullable (des NULL multiples ne violent pas une contrainte unique) ; l'app
-- fournit toujours mois, les lignes historiques sans mois restent valides.
--
-- Idempotent : to_regclass + test pg_constraint avant add constraint. ASCII
-- uniquement, pas de commentaire en fin de ligne d'instruction.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0022_rollback.sql.
-- ============================================================

-- PRE-CHECK (lecture seule, a lancer AVANT) : doublons existants qui feraient
-- echouer l'ajout de la contrainte. Attendu : 0 ligne. Si des lignes sortent,
-- dedupliquer manuellement (garder la fiche la plus recente par created_at,
-- supprimer les autres) avant d'appliquer la migration.
--   select employe_id, mois, count(*)
--     from public.paies
--    where mois is not null
--    group by employe_id, mois
--   having count(*) > 1;

do $$
begin
  if to_regclass('public.paies') is null then
    raise notice '0022: table paies absente - migration ignoree.';
    return;
  end if;

  if not exists (
    select 1
      from pg_constraint
     where conname  = 'paies_employe_mois_uniq'
       and conrelid = 'public.paies'::regclass
  ) then
    alter table public.paies
      add constraint paies_employe_mois_uniq unique (employe_id, mois);
  end if;
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule) : la contrainte existe.
-- ------------------------------------------------------------
--   select conname, pg_get_constraintdef(oid)
--     from pg_constraint
--    where conrelid = 'public.paies'::regclass
--      and conname  = 'paies_employe_mois_uniq';
--   -- attendu : 1 ligne
--   --   paies_employe_mois_uniq | UNIQUE (employe_id, mois)
-- ============================================================
