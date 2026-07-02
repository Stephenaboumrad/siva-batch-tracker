-- ============================================================
-- Rollback 0022 - Supprime la contrainte unique paies (employe_id, mois)
-- ------------------------------------------------------------
-- Restaure l'etat pre-0022. Sans la contrainte, le serveur n'empeche plus
-- deux fiches de paie identiques pour le meme employe et le meme mois : seules
-- les gardes client (bouton desactive + test STATE) subsistent.
-- Idempotent : drop constraint if exists. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.paies') is null then
    raise notice '0022 rollback: table paies absente - rien a faire.';
    return;
  end if;

  alter table public.paies
    drop constraint if exists paies_employe_mois_uniq;
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule) : la contrainte a disparu.
-- ------------------------------------------------------------
--   select conname
--     from pg_constraint
--    where conrelid = 'public.paies'::regclass
--      and conname  = 'paies_employe_mois_uniq';
--   -- attendu : 0 ligne
-- ============================================================
