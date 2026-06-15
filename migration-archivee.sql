-- ============================================================================
-- Migration : archivage des bandes (SIVA Batch Tracker)
-- À exécuter UNE FOIS dans Supabase → SQL Editor, AVANT de déployer la
-- fonctionnalité "Gestion des bandes (archiver / supprimer)".
-- Idempotent : peut être relancé sans risque.
-- ============================================================================

-- 1. Colonne d'archivage (non destructif) : une bande archivée disparaît des
--    vues actives mais conserve tout son historique en base.
alter table bandes
  add column if not exists archivee boolean not null default false;

-- 2. Index pour filtrer rapidement les bandes actives (archivee = false).
create index if not exists idx_bandes_archivee on bandes(archivee);

-- ----------------------------------------------------------------------------
-- Note sur la SUPPRESSION définitive (déjà couverte par le schéma existant) :
-- les tables enfant référencent bandes(bande_id) avec ON DELETE CASCADE
--   (saisies, intrants, aliments_phases, formulations_mp, abattages)
-- ou ON DELETE SET NULL (receptions, commandes, notifications).
-- L'application supprime malgré tout les enfants explicitement, dans l'ordre
-- (enfants -> parent), pour ne laisser aucune ligne orpheline même si une
-- contrainte différait du schéma de référence. Aucune migration requise ici.
-- ----------------------------------------------------------------------------
