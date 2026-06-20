-- ============================================================
-- Migration 0010 - ROLLBACK
-- ------------------------------------------------------------
-- Retire l'index, la FK et la colonne produit_id de lignes_commande.
-- NE TOUCHE AUCUNE donnee existante : les colonnes produit / description /
-- quantite_kg / prix_kg_fcfa / montant_fcfa restent intactes. Les lignes
-- creees via le catalogue conservent leur snapshot description et leur prix.
-- Seules la reference produit_id et sa contrainte FK disparaissent. Idempotent.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.lignes_commande') is null then
    return;
  end if;
  if exists (
    select 1 from pg_constraint
    where conname = 'lignes_commande_produit_id_fkey'
      and conrelid = 'public.lignes_commande'::regclass
  ) then
    alter table public.lignes_commande drop constraint lignes_commande_produit_id_fkey;
  end if;
  drop index if exists idx_lignes_commande_produit_id;
  alter table public.lignes_commande drop column if exists produit_id;
end $$;
