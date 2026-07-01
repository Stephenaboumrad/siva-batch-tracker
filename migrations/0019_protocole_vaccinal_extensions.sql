-- ============================================================
-- Migration 0019 - Extensions protocole_vaccinal : origine + fenetre de jour
-- ------------------------------------------------------------
-- Deux colonnes ADDITIVES sur protocole_vaccinal (0017), toutes deux necessaires
-- pour seeder le programme veto reel (0020) sans casser l'existant :
--
--   1) origine text not null default 'ferme' check in ('ferme','couvoir')
--      EXTENSIBILITE : le programme actuel est un protocole "vaccination A LA
--      FERME". Cette colonne permettra de brancher plus tard un protocole
--      "couvoir" (vaccinations realisees au couvoir) sans migration cassante.
--      Defaut 'ferme' -> toutes les lignes existantes restent "ferme". AUCUNE UI
--      couvoir livree ici. Symetrique de protocole_traitements.origine (0018).
--
--   2) jour_max int (nullable)
--      MODELISATION DES FENETRES DE JOUR (ex : le vet ecrit "J3-5"). Une ligne a
--      fenetre porte jour_cible = borne basse (debut) et jour_max = borne haute.
--      jour_max NULL = acte a jour unique (comportement 0017 inchange). Contrainte
--      jour_max >= jour_cible. Cote app, l'acte est "du" a partir de jour_cible et
--      "en retard" seulement apres jour_max.
--      Convention de jour INCHANGEE : jour_cible = age en jours, J1 = mise en place
--      (comme cycleDay). Le programme veto est note en J0 = mise en place ; il est
--      donc traduit (+1) dans le seed 0020 pour rester correct sous cette convention.
--
-- STRICTEMENT ADDITIF : aucune colonne existante supprimee ni renommee. Ne touche
-- NI le calcul des dates prevues (recalcule cote app), NI FCR/IC, NI marge, NI
-- tresorerie. Defaut 'ferme' / NULL -> NO-OP pour les lignes existantes.
--
-- Idempotent : to_regclass + add column if not exists + garde pg_constraint.
-- ASCII uniquement, pas de commentaire en fin de ligne d'instruction, pas de
-- point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0019_rollback.sql.
-- ============================================================

do $$
begin
  if to_regclass('public.protocole_vaccinal') is null then
    raise notice '0019: table protocole_vaccinal absente (0017 non applique) - migration ignoree.';
    return;
  end if;

  alter table public.protocole_vaccinal
    add column if not exists origine text not null default 'ferme';
  alter table public.protocole_vaccinal
    add column if not exists jour_max int;

  if not exists (
    select 1 from pg_constraint
    where conname = 'protocole_vaccinal_origine_chk'
      and conrelid = 'public.protocole_vaccinal'::regclass
  ) then
    alter table public.protocole_vaccinal
      add constraint protocole_vaccinal_origine_chk
      check (origine in ('ferme','couvoir'));
  end if;

  if not exists (
    select 1 from pg_constraint
    where conname = 'protocole_vaccinal_jourmax_chk'
      and conrelid = 'public.protocole_vaccinal'::regclass
  ) then
    alter table public.protocole_vaccinal
      add constraint protocole_vaccinal_jourmax_chk
      check (jour_max is null or jour_max >= jour_cible);
  end if;
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule) : les 2 colonnes existent.
-- ------------------------------------------------------------
--   select column_name, data_type, is_nullable, column_default
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'protocole_vaccinal'
--      and column_name in ('origine','jour_max')
--    order by column_name;
--   -- attendu : origine (text, NO, 'ferme'::text) ; jour_max (integer, YES, null).
-- ============================================================
