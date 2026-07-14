-- ============================================================
-- Rollback 0037 - suppression des colonnes d'instantane et de fond
--                 sur cloture_caisse
-- ------------------------------------------------------------
-- ATTENTION : les instantanes attestes aux clotures posterieures a
-- 0037 et les overrides de fond poses par le manager sont PERDUS
-- definitivement. Le front (caisse.html) tolere l'absence des colonnes
-- (repli sans instantane, fond recalcule sur compte_fcfa seul).
--
-- Idempotent : to_regclass + drop column if exists. ASCII uniquement,
-- pas de commentaire en fin de ligne d'instruction.
-- ============================================================

do $$
begin
  if to_regclass('public.cloture_caisse') is null then
    raise notice '0037_rollback: table cloture_caisse absente - ignore.';
    return;
  end if;

  alter table public.cloture_caisse drop column if exists total_mm_fcfa;
  alter table public.cloture_caisse drop column if exists total_credit_fcfa;
  alter table public.cloture_caisse drop column if exists total_depenses_fcfa;
  alter table public.cloture_caisse drop column if exists total_versements_fcfa;
  alter table public.cloture_caisse drop column if exists fond_suivant_fcfa;
  alter table public.cloture_caisse drop column if exists fond_suivant_note;

  raise notice '0037_rollback: colonnes 0037 supprimees.';
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- Plus aucune colonne 0037 (attendu : 0 ligne) :
--   select column_name from information_schema.columns
--    where table_schema = 'public'
--      and table_name = 'cloture_caisse'
--      and column_name in ('total_mm_fcfa', 'total_credit_fcfa',
--                          'total_depenses_fcfa', 'total_versements_fcfa',
--                          'fond_suivant_fcfa', 'fond_suivant_note');
-- ============================================================
