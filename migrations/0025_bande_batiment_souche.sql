-- ============================================================
-- Migration 0025 - bandes : batiment + souche (colonnes fantomes)
-- ------------------------------------------------------------
-- Audit B-F2/B-F3 : le front lit bande.batiment et bande.souche depuis
-- longtemps (etiquettes, sidebar, PDF DSV / registre / cahier) mais les
-- colonnes n'ont JAMAIS existe en base - chaque lecture retombait sur des
-- valeurs fabriquees ('Bat. A', 'Cobb 500') ou '-'. Cette migration cree
-- les colonnes reelles :
--   - batiment : nom du batiment de la bande (texte libre).
--   - souche : souche reelle de la bande (ex. Cobb 500). Le formulaire de
--     creation propose 'Cobb 500' par defaut ; la valeur est celle saisie,
--     jamais fabriquee au rendu (repli uniforme '-'). La norme de courbe
--     Cobb 500 (COBB_STANDARD) reste une reference de validation,
--     distincte de l'identite de la bande.
--
-- VUE bandes_ops : la vue assainie lue par chef_bande (0008) fige sa
-- liste de colonnes a sa creation - les nouvelles colonnes n'y
-- apparaitraient JAMAIS sans recreation. Ce fichier rejoue donc le bloc
-- 0008 (liste dynamique excluant les 3 colonnes financieres,
-- security_invoker, revoke anon + grant authenticated) APRES l'ajout des
-- colonnes. Sans cela, le manager verrait les vraies valeurs et le chef
-- verrait '-' pour toujours.
--
-- STRICTEMENT ADDITIF : 2 colonnes nullables, aucune contrainte, aucun
-- changement de policy (RLS 0021 bandes = predicats de role sans liste de
-- colonnes ; INSERT/UPDATE restent manager-only, SELECT les deux roles).
-- Le front tente l'ecriture et replie sans ces champs si la base les
-- refuse (repli a l'insertion en ligne + repli au rejeu de la file hors
-- ligne) : l'app reste fonctionnelle AVANT comme APRES cette migration.
-- Idempotent : to_regclass + add column if not exists + drop/create view.
-- ASCII uniquement, pas de commentaire en fin de ligne d'instruction, pas
-- de point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0025_rollback.sql.
-- ============================================================

do $$
declare cols text;
begin
  if to_regclass('public.bandes') is null then
    raise notice '0025: table bandes absente - migration ignoree.';
    return;
  end if;

  alter table public.bandes
    add column if not exists batiment text;
  alter table public.bandes
    add column if not exists souche text;

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
--      and column_name in ('batiment', 'souche')
--    order by column_name;
--   -- attendu : 2 lignes, is_nullable = YES partout.
--
--   select column_name
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'bandes_ops'
--      and column_name in ('batiment', 'souche', 'prix_poussin_unitaire')
--    order by column_name;
--   -- attendu : 2 lignes (batiment, souche) - la colonne financiere
--   -- prix_poussin_unitaire ne doit PAS apparaitre.
--
--   select relname, reloptions from pg_class where relname = 'bandes_ops';
--   -- attendu : 1 ligne, reloptions contient security_invoker=true.
-- ============================================================
