-- ============================================================
-- Rollback 0024 - saisies : champs cahier de batiment
-- ------------------------------------------------------------
-- Supprime les 3 colonnes cahier. PERTE DE DONNEES : les valeurs deja
-- saisies dans temperature_observee_c / observations / signes_observes
-- sont perdues. Les colonnes historiques (eau_consommee_l,
-- temperature_c, humidite_pct) ne sont pas touchees.
-- Le front tolere l'absence des colonnes (repli d'insertion en ligne +
-- repli au rejeu de la file hors ligne) : aucun deploiement n'est requis
-- avant ce rollback.
-- Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.saisies') is null then
    raise notice '0024 rollback: table saisies absente - rien a faire.';
    return;
  end if;

  alter table public.saisies drop column if exists signes_observes;
  alter table public.saisies drop column if exists observations;
  alter table public.saisies drop column if exists temperature_observee_c;
end $$;
