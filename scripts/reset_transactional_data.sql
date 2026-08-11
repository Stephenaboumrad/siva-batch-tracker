-- ============================================================
-- Script ops - Purge des donnees transactionnelles (pre-J0 bande 1)
-- REVISION 3 (2026-08-11) : ARBITRAGE INTEGRE - les quatre decisions de
-- Stephen sont dans le flux standard, plus rien d'optionnel :
--   1. clients CONSERVES (reference) - confirme, deja le cas en rev 2.
--   2. remise a zero des solde_fcfa = OBLIGATOIRE (section 7), avec
--      piste d'audit NOTICE par client (ancien solde trace).
--   3. stocks et intrants : PURGE COMPLETE (delete), pas de variante
--      quantite = 0 ; aliments_phases / formulations_mp purgees.
--   4. fiches de test employes SIVA-010 et clients CLI-TEST-001 :
--      suppression ACTIVE (section 7, plus commentee).
-- REVISION 2 (2026-08) : tables RH 0045-0047 (pointages, absences,
-- avances), clients passes en REFERENCE, garde GO-LIVE en tete.
-- ------------------------------------------------------------
-- CE SCRIPT EST DESTRUCTIF ET SANS ROLLBACK.
-- AVANT D'EXECUTER : exporter chaque table en CSV depuis le dashboard
-- Supabase (Table Editor > Export). Le CSV est la SEULE voie de
-- recuperation - il n'existe pas de _rollback.sql pour une purge.
--
-- REGLE ABSOLUE (CLAUDE.md) : CE SCRIPT NE DOIT JAMAIS ETRE EXECUTE
-- APRES J0 (mise en place de la bande 1 reelle). Cette revision prepare
-- l'UNIQUE execution finale legitime, juste avant J0. La garde de la
-- section 0 doit etre ARMEE avant cette execution (voir ci-dessous).
--
-- Objet : vider les 28 tables transactionnelles (donnees fictives des
-- dry runs + activite de test RH/B2B) pour que la bande 1 demarre sur
-- une base propre, SANS toucher aux 12 tables de reference/seed, aux
-- fiches clients, ni a auth.users.
--
-- Ce n'est PAS une migration numerotee : aucun changement de schema,
-- aucune politique RLS modifiee, re-executable a volonte (idempotent -
-- une table deja vide est re-videe a 0 ligne).
--
-- Tables PURGEES (28, enfants avant parents) :
--   POS / caisse   : lignes_transaction, paiements, cloture_caisse,
--                    pos_transactions, mouvements_stock
--   Commandes      : lignes_commande, commandes
--   Suivi de bande : vaccinations, traitements, saisies, intrants,
--                    aliments_phases, formulations_mp, abattages,
--                    vides_sanitaires, non_conformites, bandes
--   Supply chain   : inspections, receptions, stocks
--   RH             : pointages, absences, avances, paies, depenses_rh
--   Divers         : notifications, releves_nuisibles, etalonnages
--
-- Tables CONSERVEES (13, reference/seed) : sites, points_de_vente,
--   profiles, employes, produits, matieres, fournisseurs,
--   protocole_vaccinal, protocole_traitements, parametres, equipements,
--   postes_appatage, et desormais CLIENTS (fiches reelles - la revision
--   1 les purgait ; les commandes/transactions de test qui les
--   referencent partent, les fiches restent).
--
-- RESIDUS DE TEST dans les tables de reference (section 7 - ARBITRE,
-- flux STANDARD) :
--   - employes : fiche de test SIVA-010 SUPPRIMEE
--   - clients  : fiche de test CLI-TEST-001 SUPPRIMEE
--   - clients.solde_fcfa : remis a zero (transactions de test purgees,
--     un solde residuel serait un mensonge comptable) - chaque solde
--     non nul est trace en NOTICE avant l'ecrasement (piste d'audit)
--
-- auth.users N'EST PAS TOUCHABLE par ce script - NETTOYAGE MANUEL au
-- dashboard Supabase (Authentication > Users) APRES l'execution :
--   [ ] compte employe de test  : siva-010@coqorico.internal
--   [ ] compte client de test   : client-test (e-mail du compte
--       CLI-TEST-001 - verifier dans la fiche avant purge)
--   Les comptes reels (SIVA-001/002/003, employes reels, clients
--   reels) NE SONT PAS touches.
--
-- Precautions techniques :
--   - DELETE uniquement, jamais TRUNCATE ... CASCADE (le cascade est
--     exactement ce qui tuerait les seeds). Ordre explicite enfants ->
--     parents ; aucune SQL dynamique au-dela du format(%I) de la
--     boucle sur la liste EXPLICITE ci-dessus.
--   - Chaque table est gardee par to_regclass : une table absente est
--     ignoree proprement (tables heritees sans DDL dans le depot - on
--     ne presume de rien).
--   - Les triggers bandes_delete_guard (0021), commandes_paiement_guard
--     (0014) et pointages_horodatage (0045) autorisent le contexte sans
--     JWT : les DELETE passent dans le SQL Editor.
--   - PK uuid/texte generees cote client ou par defaut : AUCUNE
--     sequence a reinitialiser (aucune colonne serial/identity dans le
--     schema du depot ; la verification liste pg_sequences pour le
--     confirmer sur la base reelle).
--
-- PROCEDURE DU RUN FINAL PRE-J0 (9 etapes, dans l'ordre) :
--   1. Exporter les tables en CSV (dashboard > Table Editor) - seule
--      voie de recuperation.
--   2. Lancer le cross-check de perimetre (VERIFICATION 2b) : toute
--      table hors liste = a classer et integrer au script D'ABORD.
--   3. ARMER la garde (section 0 : go_live = date de mise en place
--      reelle) et remplir la DATE D'EXECUTION ci-dessous.
--   4. Executer le script ; lire les NOTICEs (garde, compte par table,
--      piste d'audit des soldes remis a zero).
--   5. Lire la VERIFICATION : 0 partout en B (y compris les lignes
--      fiches de test et soldes non nuls), > 0 en A, clients = INFO.
--   6. Requete sequences (VERIFICATION 2a) : 0 ligne attendue.
--   7. Nettoyage MANUEL auth.users (checklist ci-dessus).
--   8. INVENTAIRE D'OUVERTURE - APRES le reset, AVANT l'arrivee des
--      poussins : compter physiquement le stock reel (aliment, produits
--      veterinaires, consommables) et le SAISIR A NEUF dans l'app
--      (receptions/stocks dates du jour). Le premier cycle demarre sur
--      un stock VRAI et date, jamais sur des residus corriges.
--   9. Confirmer, committer la date remplie en en-tete.
--
-- DATE D'EXECUTION FINALE : ____-__-__ (a remplir a la main lors de
-- l'unique run pre-J0, puis committer la trace).
--
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor (role proprietaire).
-- ============================================================

begin;

-- ------------------------------------------------------------
-- 0) GARDE GO-LIVE - a ARMER avant l'execution finale.
--    go_live = NULL  -> garde DESARMEE (dry runs pre-J0) : le script
--                       previent bruyamment mais s'execute.
--    go_live = date  -> ARMEE : s'il existe une bande dont date_entree
--                       >= go_live (bande REELLE), ABORT IMMEDIAT de
--                       toute la transaction, message explicite.
--    ARMEMENT (procedure pre-J0) : remplacer null par la date de mise
--    en place reelle prevue, ex. date '2026-09-01'. Apres J0, la garde
--    armee rend le script INEXECUTABLE - c'est voulu et definitif.
-- ------------------------------------------------------------
do $$
declare
  go_live constant date := null;
  n bigint;
begin
  if go_live is null then
    raise notice 'reset GARDE: NON ARMEE (go_live = null) - execution pre-J0 assumee. ARMER avant le run final.';
    return;
  end if;
  if to_regclass('public.bandes') is null then
    raise notice 'reset GARDE: table bandes absente - rien a proteger.';
    return;
  end if;
  select count(*) into n from public.bandes where date_entree >= go_live;
  if n > 0 then
    raise exception 'reset GARDE: % bande(s) avec date_entree >= % (cycle REEL detecte). CE SCRIPT NE DOIT JAMAIS ETRE EXECUTE APRES J0 - transaction annulee.', n, go_live;
  end if;
  raise notice 'reset GARDE: armee sur % - aucune bande reelle detectee, purge autorisee.', go_live;
end $$;

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
-- 2) Commandes - lignes avant en-tetes (paiements deja purges en 1).
--    Les fiches clients referencees SURVIVENT (revision 2).
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
-- 5) RH (REVISION 2 : + pointages / absences / avances, 0045-0047) -
--    employes, postes_appatage et equipements survivent, seuls leurs
--    journaux sont purges. Aucune FK entre les tables RH (references
--    souples par matricule / paie_id texte) - l'ordre est libre, on
--    purge les journaux avant paies par lisibilite.
-- ------------------------------------------------------------
do $$
declare
  t text;
  n bigint;
begin
  foreach t in array array[
    'pointages',
    'absences',
    'avances',
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
-- 6) Clients : CONSERVES (arbitrage confirme - fiches reelles du
--    portail B2B). La revision 1 purgait la table entiere ; seuls les
--    residus de test et les soldes fantomes partent (section 7).
-- ------------------------------------------------------------
do $$
begin
  raise notice 'reset: clients - CONSERVES (fiches reelles). Residus + soldes : section 7.';
end $$;

-- ------------------------------------------------------------
-- 7) RESIDUS DE TEST + SOLDES - ARBITRE 2026-08-11, FLUX STANDARD.
--    (Les enfants transactionnels sont deja purges au-dessus : ces
--    DELETE ne peuvent pas casser de FK.)
-- ------------------------------------------------------------
do $$
declare
  r record;
  n bigint;
begin
  -- (a) Fiche employe de test SIVA-010 (RH-1/RH-2). Son compte
  --     auth.users se supprime A LA MAIN au dashboard (voir en-tete).
  if to_regclass('public.employes') is null then
    raise notice 'reset residus: table employes absente - ignoree.';
  else
    delete from public.employes where matricule = 'SIVA-010';
    get diagnostics n = row_count;
    raise notice 'reset residus: employes SIVA-010 - % ligne(s).', n;
  end if;

  if to_regclass('public.clients') is null then
    raise notice 'reset residus: table clients absente - ignoree.';
    return;
  end if;

  -- (b) Fiche client de test CLI-TEST-001 (recette B2B). Compte auth
  --     a supprimer A LA MAIN egalement.
  delete from public.clients where client_id = 'CLI-TEST-001';
  get diagnostics n = row_count;
  raise notice 'reset residus: clients CLI-TEST-001 - % ligne(s).', n;

  -- (c) Remise a zero OBLIGATOIRE des soldes clients (les transactions
  --     de test sont purgees : un solde residuel serait un mensonge
  --     comptable). PISTE D'AUDIT : chaque solde non nul est trace en
  --     NOTICE avec sa valeur AVANT l'ecrasement.
  for r in
    select client_id, solde_fcfa from public.clients
     where coalesce(solde_fcfa, 0) <> 0
     order by client_id
  loop
    raise notice 'reset soldes: client % - ancien solde % FCFA remis a 0.', r.client_id, r.solde_fcfa;
  end loop;
  update public.clients set solde_fcfa = 0 where coalesce(solde_fcfa, 0) <> 0;
  get diagnostics n = row_count;
  raise notice 'reset soldes: % client(s) remis a zero.', n;
end $$;

commit;

-- ============================================================
-- VERIFICATION (lecture seule, s'execute apres le commit).
-- ------------------------------------------------------------
-- Une ligne par controle (44 : 41 tables + 3 controles d'arbitrage).
-- Colonne statut :
--   OK        = groupe B a 0 ligne, ou groupe A avec au moins 1 ligne
--   ANOMALIE  = un survivant en B, ou une table de reference videe en A
--   INFO      = groupe C (clients : ARBITRE conserve - compte affiche a
--               titre informatif, 0 est legitime si aucune fiche reelle
--               n'existe encore)
--   ABSENTE   = table inexistante (migration jamais executee)
-- Les 3 controles d'arbitrage (groupe B, attendu 0) :
--   employes [fiche test SIVA-010], clients [fiche test CLI-TEST-001],
--   clients [solde_fcfa <> 0].
-- Les lignes non-OK remontent EN TETE du resultat.
-- ============================================================
with etat as (
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
    ('B', 'pointages',             '0'),
    ('B', 'absences',              '0'),
    ('B', 'avances',               '0'),
    ('B', 'paies',                 '0'),
    ('B', 'depenses_rh',           '0'),
    ('B', 'notifications',         '0'),
    ('B', 'releves_nuisibles',     '0'),
    ('B', 'etalonnages',           '0'),
    ('B', 'bandes',                '0'),
    ('C', 'clients',               'info (conserves)')
  ) as v(groupe, table_name, attendu)

  union all
  select 'B', 'employes [fiche test SIVA-010]', '0',
         case when to_regclass('public.employes') is null then null
              else (select count(*) from public.employes where matricule = 'SIVA-010') end

  union all
  select 'B', 'clients [fiche test CLI-TEST-001]', '0',
         case when to_regclass('public.clients') is null then null
              else (select count(*) from public.clients where client_id = 'CLI-TEST-001') end

  union all
  select 'B', 'clients [solde_fcfa <> 0]', '0',
         case when to_regclass('public.clients') is null then null
              else (select count(*) from public.clients where coalesce(solde_fcfa, 0) <> 0) end
)
select groupe, table_name, attendu, lignes,
       case
         when lignes is null                then 'ABSENTE'
         when groupe = 'C'                  then 'INFO'
         when groupe = 'B' and lignes = 0   then 'OK'
         when groupe = 'A' and lignes > 0   then 'OK'
         else 'ANOMALIE'
       end as statut
from etat
order by case when lignes is null then 1
              when groupe = 'C' then 1
              when groupe = 'B' and lignes = 0 then 2
              when groupe = 'A' and lignes > 0 then 2
              else 0
         end,
         groupe, table_name;

-- ------------------------------------------------------------
-- VERIFICATION 2 (lecture seule) : sequences et cross-check du perimetre.
-- ------------------------------------------------------------
-- (a) Sequences (attendu : 0 ligne - PK uuid/texte partout ; si une
--     ligne sort, decider de son reset a la main) :
--   select schemaname, sequencename, last_value
--     from pg_sequences where schemaname = 'public';
--
-- (b) Cross-check du perimetre : toute table de public ABSENTE de la
--     liste des 41 ci-dessus = creee hors migrations -> a classer et a
--     ajouter au script AVANT le run final :
--   select table_name from information_schema.tables
--    where table_schema = 'public' and table_type = 'BASE TABLE'
--      and table_name not in (
--        'sites','points_de_vente','profiles','employes','produits',
--        'matieres','fournisseurs','protocole_vaccinal',
--        'protocole_traitements','parametres','equipements',
--        'postes_appatage','lignes_transaction','paiements',
--        'cloture_caisse','pos_transactions','mouvements_stock',
--        'lignes_commande','commandes','vaccinations','traitements',
--        'saisies','intrants','aliments_phases','formulations_mp',
--        'abattages','vides_sanitaires','non_conformites','inspections',
--        'receptions','stocks','pointages','absences','avances','paies',
--        'depenses_rh','notifications','releves_nuisibles','etalonnages',
--        'bandes','clients'
--      )
--    order by table_name;
-- ============================================================
