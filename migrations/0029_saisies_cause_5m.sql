-- ============================================================
-- Migration 0029 - saisies.cause_5m : categorisation 5M de la mortalite
-- ------------------------------------------------------------
-- Quand un indicateur derive (mortalite), l'axe fonctionnel systemique
-- diagnostique la cause racine via les 5M (Main-d'oeuvre / Matiere /
-- Materiel / Methode / Milieu). Les signes observes restent du texte
-- libre factuel (0024) ; cette colonne ajoute un PRE-CLASSEMENT 5M
-- optionnel par saisie journaliere, pour rendre les observations
-- terrain ANALYSABLES (repartition par categorie sur la fiche bande).
--
-- FORMAT : tableau jsonb de cles STABLES parmi
--   ["main_doeuvre","matiere","materiel","methode","milieu"]
-- (libelles geres cote front ; jsonb plutot que text[] pour rester
-- aligne sur la convention 0028 et eviter tout piege d'echappement).
-- Zero ou plusieurs categories par saisie - null/absent = non categorise.
-- Aucune contrainte CHECK a dessein : le vocabulaire est tenu par le
-- front (CAUSES_5M), une contrainte figerait les cles dans la base.
--
-- AUCUNE nouvelle policy : cause_5m suit la RLS existante de saisies
-- (lecture/ecriture par bande selon les policies 0007/0021 en place).
-- Le front (index.html) tolere la colonne absente : insert rejoue sans
-- elle + avertissement, en ligne comme au rejeu de la file hors ligne
-- (meme discipline que 0024/0025).
--
-- INDEPENDANTE de 0024 : s'applique avant ou apres, aucun prerequis
-- autre que l'existence de la table saisies.
--
-- Idempotent : to_regclass + add column if not exists. ASCII uniquement,
-- pas de commentaire en fin de ligne d'instruction.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0029_rollback.sql.
-- ============================================================

do $$
begin
  if to_regclass('public.saisies') is null then
    raise notice '0029: table saisies absente - migration ignoree.';
    return;
  end if;

  alter table public.saisies
    add column if not exists cause_5m jsonb;
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- 1. Colonne presente :
--   select column_name, data_type from information_schema.columns
--    where table_schema = 'public' and table_name = 'saisies'
--      and column_name = 'cause_5m';
--   -- attendu : 1 ligne, cause_5m jsonb.
--
-- 2. Aucune policy nouvelle attendue sur saisies (inchangees) :
--   select policyname from pg_policies
--    where schemaname = 'public' and tablename = 'saisies'
--    order by policyname;
--   -- attendu : la meme liste qu'avant 0029.
-- ============================================================
