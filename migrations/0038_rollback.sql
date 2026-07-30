-- ============================================================
-- Rollback 0038 - retire les colonnes de detail poussins de receptions
-- ------------------------------------------------------------
-- DESTRUCTIF pour les valeurs deja saisies dans ces 3 colonnes
-- (effectif_commande / mortalite_transport / poids_moyen_g) : exporter
-- la table en CSV avant si des receptions poussins ont ete enregistrees.
-- Les autres colonnes et les politiques RLS ne sont pas touchees.
-- Idempotent : drop column if exists.
-- ============================================================

do $$
begin
  if to_regclass('public.receptions') is null then
    raise notice '0038 rollback: table receptions absente - rien a faire.';
    return;
  end if;

  alter table public.receptions drop column if exists effectif_commande;
  alter table public.receptions drop column if exists mortalite_transport;
  alter table public.receptions drop column if exists poids_moyen_g;

  raise notice '0038 rollback: colonnes de detail poussins retirees.';
end $$;

-- VERIFICATION (attendu : 0 ligne) :
--   select column_name from information_schema.columns
--    where table_schema = 'public'
--      and table_name = 'receptions'
--      and column_name in ('effectif_commande', 'mortalite_transport', 'poids_moyen_g');
