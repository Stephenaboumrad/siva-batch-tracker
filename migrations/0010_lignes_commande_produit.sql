-- ============================================================
-- Migration 0010 - Pont catalogue -> lignes_commande
--   ajoute lignes_commande.produit_id (FK NULLABLE vers produits).
-- ------------------------------------------------------------
-- STRICTEMENT ADDITIF. Aucune colonne existante supprimee ni renommee. La
-- colonne est NULLABLE : toutes les lignes existantes restent identiques
-- (produit_id NULL, produit / description / quantite_kg / prix_kg_fcfa /
-- montant_fcfa inchanges). Le calcul du montant (quantite_kg x prix_kg_fcfa)
-- n'est PAS touche, et montant_total_fcfa des commandes existantes non plus.
--
-- Snapshot du nom de produit : on REUTILISE la colonne existante description
-- (deja par-ligne, gelee a la creation, affichee partout comme libelle de
-- ligne) donc AUCUNE nouvelle colonne de nom n'est necessaire.
--
-- RLS : INCHANGEE. lignes_commande reste sous rls7_internal_all. Ajouter une
-- colonne ne requiert aucun changement de policy, donc aucune instruction RLS
-- n'est presente dans ce fichier.
--
-- ON DELETE SET NULL : supprimer un produit du catalogue ne casse jamais une
-- ligne historique (produit_id repasse a NULL, le snapshot description demeure).
--
-- Idempotent, to_regclass / IF NOT EXISTS guarde. Hygiene 0009 : ASCII, pas de
-- commentaire en fin de ligne d'instruction, pas de point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0010_rollback.sql.
-- ============================================================

do $$
begin
  if to_regclass('public.lignes_commande') is null then
    raise notice 'Table lignes_commande absente - migration ignoree.';
    return;
  end if;

  alter table public.lignes_commande add column if not exists produit_id text;

  if to_regclass('public.produits') is not null
     and not exists (
       select 1 from pg_constraint
       where conname = 'lignes_commande_produit_id_fkey'
         and conrelid = 'public.lignes_commande'::regclass
     ) then
    alter table public.lignes_commande
      add constraint lignes_commande_produit_id_fkey
      foreign key (produit_id) references public.produits(produit_id) on delete set null;
  end if;
end $$;

create index if not exists idx_lignes_commande_produit_id on public.lignes_commande(produit_id);
