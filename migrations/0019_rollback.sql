-- ============================================================
-- Rollback 0019 - Extensions protocole_vaccinal
-- ------------------------------------------------------------
-- Retire les colonnes origine et jour_max (et leurs contraintes, qui tombent
-- avec les colonnes). Idempotent (drop column if exists). ASCII uniquement.
-- NB : si le seed 0020 a ete applique, les lignes seedees restent (jour_cible /
-- voie / note conserves) ; seules les 2 colonnes ajoutees disparaissent.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.protocole_vaccinal') is null then
    raise notice '0019 rollback: table protocole_vaccinal absente - rien a faire.';
    return;
  end if;

  alter table public.protocole_vaccinal drop column if exists jour_max;
  alter table public.protocole_vaccinal drop column if exists origine;
end $$;
