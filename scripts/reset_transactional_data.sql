-- ============================================================
-- Script ops - Purge des donnees transactionnelles (dry run bande 1)
-- ------------------------------------------------------------
-- CE SCRIPT EST DESTRUCTIF ET SANS ROLLBACK.
-- AVANT D'EXECUTER : exporter chaque table en CSV depuis le dashboard
-- Supabase (Table Editor > Export). Le CSV est la SEULE voie de
-- recuperation - il n'existe pas de _rollback.sql pour une purge de donnees.
--
-- Objet : vider les 26 tables transactionnelles (donnees fictives du dry
-- run) pour que la bande 1 demarre sur une base propre, SANS toucher aux
-- 12 tables de reference/seed ni a auth.users.
--
-- Ce n'est PAS une migration numerotee : aucun changement de schema, pas de
-- politique RLS modifiee, re-executable a volonte (idempotent - une table
-- deja vide est simplement re-videe a 0 ligne).
--
-- Tables PURGEES (26, enfants avant parents, clients en tout dernier) :
--   POS / caisse   : lignes_transaction, paiements, cloture_caisse,
--                    pos_transactions, mouvements_stock
--   Commandes      : lignes_commande, commandes
--   Suivi de bande : vaccinations, traitements, saisies, intrants,
--                    aliments_phases, formulations_mp, abattages,
--                    vides_sanitaires, non_conformites, bandes
--   Supply chain   : inspections, receptions, stocks
--   RH / divers    : paies, depenses_rh, notifications,
--                    releves_nuisibles, etalonnages
--   Dernier        : clients
--
-- Tables CONSERVEES (12, reference/seed) : sites, points_de_vente,
--   profiles, employes, produits, matieres, fournisseurs,
--   protocole_vaccinal, protocole_traitements, parametres, equipements,
--   postes_appatage.
--
-- auth.users n'est PAS touche : les comptes Auth orphelins (ex-clients de
-- test) sont nettoyes a la main apres coup.
--
-- Precautions techniques :
--   - DELETE uniquement, jamais TRUNCATE ... CASCADE (le cascade est
--     exactement ce qui tuerait les seeds).
--   - Chaque table est gardee par to_regclass : une table absente est
--     ignoree proprement (18 tables heritees n'ont pas de DDL dans le
--     depot - on ne presume de rien).
--   - Les triggers bandes_delete_guard (0021) et commandes_paiement_guard
--     (0014) autorisent le contexte sans JWT : les DELETE passent dans le
--     SQL Editor.
--   - PK uuid generees cote client : aucune sequence a reinitialiser.
--
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor (role proprietaire).
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 1) POS / caisse - enfants de pos_transactions d'abord, puis
--    mouvements_stock (reference stocks et bandes, purges plus bas)
-- ------------------------------------------------------------
do $$
declare
  t text;
  n bigint;
begin
  foreach t in array array[
    'lignes_transaction',
    'paiements',
    'cloture_caisse',
    'pos_transactions',
    'mouvements_stock'
  ] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice 'reset: table % absente - ignoree.', t;
      continue;
    end if;
    execute format('delete from public.%I', t);
    get diagnostics n = row_count;
    raise notice 'reset: % - % ligne(s) supprimee(s).', t, n;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 2) Commandes - lignes avant en-tetes (paiements deja purges en 1)
-- ------------------------------------------------------------
do $$
declare
  t text;
  n bigint;
begin
  foreach t in array array[
    'lignes_commande',
    'commandes'
  ] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice 'reset: table % absente - ignoree.', t;
      continue;
    end if;
    execute format('delete from public.%I', t);
    get diagnostics n = row_count;
    raise notice 'reset: % - % ligne(s) supprimee(s).', t, n;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 3) Suivi de bande - tous les enfants de bandes, puis bandes.
--    aliments_phases et formulations_mp sont bien du per-bande
--    (bande_id), malgre leurs noms de catalogue.
-- ------------------------------------------------------------
do $$
declare
  t text;
  n bigint;
begin
  foreach t in array array[
    'vaccinations',
    'traitements',
    'saisies',
    'intrants',
    'aliments_phases',
    'formulations_mp',
    'abattages',
    'vides_sanitaires',
    'non_conformites',
    'bandes'
  ] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice 'reset: table % absente - ignoree.', t;
      continue;
    end if;
    execute format('delete from public.%I', t);
    get diagnostics n = row_count;
    raise notice 'reset: % - % ligne(s) supprimee(s).', t, n;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 4) Supply chain - inspections avant receptions, stocks en dernier
--    (mouvements_stock qui le reference est deja purge en 1)
-- ------------------------------------------------------------
do $$
declare
  t text;
  n bigint;
begin
  foreach t in array array[
    'inspections',
    'receptions',
    'stocks'
  ] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice 'reset: table % absente - ignoree.', t;
      continue;
    end if;
    execute format('delete from public.%I', t);
    get diagnostics n = row_count;
    raise notice 'reset: % - % ligne(s) supprimee(s).', t, n;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 5) RH / divers - employes, postes_appatage et equipements survivent,
--    seuls leurs journaux sont purges
-- ------------------------------------------------------------
do $$
declare
  t text;
  n bigint;
begin
  foreach t in array array[
    'paies',
    'depenses_rh',
    'notifications',
    'releves_nuisibles',
    'etalonnages'
  ] loop
    if to_regclass(format('public.%I', t)) is null then
      raise notice 'reset: table % absente - ignoree.', t;
      continue;
    end if;
    execute format('delete from public.%I', t);
    get diagnostics n = row_count;
    raise notice 'reset: % - % ligne(s) supprimee(s).', t, n;
  end loop;
end $$;

-- ------------------------------------------------------------
-- 6) Clients - EN TOUT DERNIER : pos_transactions, paiements et
--    commandes qui le referencent sont deja purges (1 et 2).
--    auth.users n'est pas touche (nettoyage manuel apres coup).
-- ------------------------------------------------------------
do $$
declare
  n bigint;
begin
  if to_regclass('public.clients') is null then
    raise notice 'reset: table clients absente - ignoree.';
    return;
  end if;
  delete from public.clients;
  get diagnostics n = row_count;
  raise notice 'reset: clients - % ligne(s) supprimee(s).', n;
end $$;

commit;

-- ============================================================
-- VERIFICATION (lecture seule, s'execute apres le commit).
-- ------------------------------------------------------------
-- Une ligne par table (38). Colonne statut :
--   OK       = groupe B a 0 ligne, ou groupe A avec au moins 1 ligne
--   ANOMALIE = un survivant en B, ou une table de reference videe en A
--   ABSENTE  = table inexistante (migration jamais executee)
-- Les lignes non-OK remontent EN TETE du resultat.
-- ============================================================
select groupe, table_name, attendu, lignes,
       case
         when lignes is null                then 'ABSENTE'
         when groupe = 'B' and lignes = 0   then 'OK'
         when groupe = 'A' and lignes > 0   then 'OK'
         else 'ANOMALIE'
       end as statut
from (
  select v.groupe, v.table_name, v.attendu,
         case when to_regclass('public.' || v.table_name) is null then null
              else (xpath('/row/c/text()', query_to_xml(
                     format('select count(*) as c from public.%I', v.table_name),
                     false, true, '')))[1]::text::bigint
         end as lignes
  from (values
    ('A', 'sites',                 '> 0'),
    ('A', 'points_de_vente',       '> 0'),
    ('A', 'profiles',              '> 0'),
    ('A', 'employes',              '> 0'),
    ('A', 'produits',              '> 0'),
    ('A', 'matieres',              '> 0'),
    ('A', 'fournisseurs',          '> 0'),
    ('A', 'protocole_vaccinal',    '> 0'),
    ('A', 'protocole_traitements', '> 0'),
    ('A', 'parametres',            '> 0'),
    ('A', 'equipements',           '> 0'),
    ('A', 'postes_appatage',       '> 0'),
    ('B', 'lignes_transaction',    '0'),
    ('B', 'paiements',             '0'),
    ('B', 'cloture_caisse',        '0'),
    ('B', 'pos_transactions',      '0'),
    ('B', 'mouvements_stock',      '0'),
    ('B', 'lignes_commande',       '0'),
    ('B', 'commandes',             '0'),
    ('B', 'vaccinations',          '0'),
    ('B', 'traitements',           '0'),
    ('B', 'saisies',               '0'),
    ('B', 'intrants',              '0'),
    ('B', 'aliments_phases',       '0'),
    ('B', 'formulations_mp',       '0'),
    ('B', 'abattages',             '0'),
    ('B', 'vides_sanitaires',      '0'),
    ('B', 'non_conformites',       '0'),
    ('B', 'inspections',           '0'),
    ('B', 'receptions',            '0'),
    ('B', 'stocks',                '0'),
    ('B', 'paies',                 '0'),
    ('B', 'depenses_rh',           '0'),
    ('B', 'notifications',         '0'),
    ('B', 'releves_nuisibles',     '0'),
    ('B', 'etalonnages',           '0'),
    ('B', 'bandes',                '0'),
    ('B', 'clients',               '0')
  ) as v(groupe, table_name, attendu)
) t
order by case when lignes is null then 1
              when groupe = 'B' and lignes = 0 then 2
              when groupe = 'A' and lignes > 0 then 2
              else 0
         end,
         groupe, table_name;
