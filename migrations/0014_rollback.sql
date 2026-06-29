-- ============================================================
-- Migration 0014 - ROLLBACK
-- ------------------------------------------------------------
-- Retire le trigger, la fonction garde-fou, la RPC mark_commande_paiement et
-- les colonnes de paiement de commandes. NE TOUCHE AUCUNE autre donnee : statut,
-- montant_total_fcfa, lignes_commande, etc. restent intacts. Les valeurs de
-- statut_paiement / date_paiement / mode_paiement deja saisies sont perdues avec
-- les colonnes (c'est le but d'un rollback). Idempotent.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

drop trigger   if exists commandes_paiement_guard on public.commandes;
drop function  if exists public.trg_commandes_paiement_guard();
drop function  if exists public.mark_commande_paiement(text, text, timestamptz, text);

do $$
begin
  if to_regclass('public.commandes') is null then
    return;
  end if;
  alter table public.commandes drop constraint if exists commandes_statut_paiement_chk;
  alter table public.commandes drop constraint if exists commandes_mode_paiement_chk;
  alter table public.commandes drop column if exists mode_paiement;
  alter table public.commandes drop column if exists date_paiement;
  alter table public.commandes drop column if exists statut_paiement;
end $$;
