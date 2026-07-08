-- ============================================================
-- Migration 0030 - bandes.surface_m2 : densite d'elevage calculable
-- ------------------------------------------------------------
-- La note de cadrage liste la densite (oiseaux/m2) comme indicateur et
-- futur facteur DOE, mais AUCUNE colonne ne la supporte (constat G1 de
-- l'audit PR #114) : densite = effectif / surface, il faut la surface.
--   - surface_m2 : surface du batiment de la bande, en m2 (numeric,
--     nullable, optionnelle). Saisie au formulaire de creation de bande.
--     Si absente ou vide, le front affiche "densite non calculable" -
--     jamais un zero fabrique.
--
-- VUE bandes_ops : la vue assainie lue par chef_bande (0008) fige sa
-- liste de colonnes a sa creation - ce fichier rejoue donc le bloc 0008
-- (liste dynamique excluant les 3 colonnes financieres, security_invoker,
-- revoke anon + grant authenticated) APRES l'ajout de la colonne, comme
-- 0025. La liste etant dynamique, 0025 et 0030 peuvent etre appliquees
-- dans N'IMPORTE QUEL ordre : la derniere executee reconstruit la vue
-- avec toutes les colonnes presentes.
--
-- STRICTEMENT ADDITIF : 1 colonne nullable, aucune contrainte, AUCUNE
-- nouvelle policy (RLS 0021 bandes = predicats de role sans liste de
-- colonnes ; INSERT/UPDATE restent manager-only, SELECT les deux roles).
-- Le front tente l'ecriture et replie sans surface_m2 si la base la
-- refuse (repli a l'insertion en ligne + repli au rejeu de la file hors
-- ligne, groupe independant de 0025) : l'app reste fonctionnelle AVANT
-- comme APRES cette migration.
-- Idempotent : to_regclass + add column if not exists + drop/create view.
-- ASCII uniquement, pas de commentaire en fin de ligne d'instruction, pas
-- de point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0030_rollback.sql.
-- ============================================================

do $$
declare cols text;
begin
  if to_regclass('public.bandes') is null then
    raise notice '0030: table bandes absente - migration ignoree.';
    return;
  end if;

  alter table public.bandes
    add column if not exists surface_m2 numeric;

  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into cols
  from information_schema.columns
  where table_schema = 'public'
    and table_name   = 'bandes'
    and column_name not in ('prix_poussin_unitaire', 'cout_aliment_kg', 'prix_vente_carcasse_kg');

  execute 'drop view if exists public.bandes_ops';
  execute 'create view public.bandes_ops with (security_invoker = true) as select '
          || cols || ' from public.bandes';

  execute 'revoke all on public.bandes_ops from anon';
  execute 'grant select on public.bandes_ops to authenticated';
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
--   select column_name, data_type, is_nullable
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'bandes'
--      and column_name = 'surface_m2';
--   -- attendu : 1 ligne, numeric, is_nullable = YES.
--
--   select column_name
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'bandes_ops'
--      and column_name in ('surface_m2', 'prix_poussin_unitaire')
--    order by column_name;
--   -- attendu : 1 ligne (surface_m2) - la colonne financiere
--   -- prix_poussin_unitaire ne doit PAS apparaitre.
--
--   select relname, reloptions from pg_class where relname = 'bandes_ops';
--   -- attendu : 1 ligne, reloptions contient security_invoker=true.
-- ============================================================
