-- ============================================================
-- Migration 0050 - Doctrine des dates : date d'evenement fixee par le
--                  systeme pour les roles non-manager (BEFORE INSERT)
-- ------------------------------------------------------------
-- PRINCIPE (decision proprietaire) : pour un EVENEMENT, la date est
-- posee par le SERVEUR, l'utilisateur la voit seulement. Generalise le
-- principe 0045 (heure serveur pour les pointages) aux declarations.
-- Les dates de PERIODE/PLANNING (absences du/au, protocole, vides
-- sanitaires, date de livraison souhaitee) restent SAISIES - elles
-- SONT la donnee, aucun trigger.
--
-- ARBITRAGE (cas limite remonte AVANT implementation, tranche par
-- Stephen 2026-08-12) - FORMULE HYBRIDE pour 3 tables a date
-- d'observation RETRO-DATABLE :
--   saisies (date_saisie), vaccinations (date_faite / "date reelle"),
--   traitements (date_traitement).
--   -> Ces 3 tables N'ONT PAS DE TRIGGER ici : la date du jour est
--      GELEE cote FRONT (lecture seule) avec un clic "Modifier"
--      explicite qui debloque le selecteur (transcription du cahier le
--      lendemain ; date_traitement pilote le delai d'attente abattage -
--      un back-dating clinique doit atteindre la base). La tracabilite
--      est assuree par le JOURNAL 0049 (toute date choisie y est
--      capturee) : controle par l'audit, pas barriere serveur.
--
-- releves_nuisibles : EXCLU aussi. Sa date de tournee sert a
--   SELECTIONNER et EDITER une tournee passee (rls35 : le chef edite
--   son releve du jour) - un "force aujourd'hui" y perdrait
--   silencieusement la date choisie. Traite comme l'hybride (saisie
--   deliberee, journal 0049), sans trigger.
--
-- PERIMETRE REEL DU TRIGGER (7 tables) : receptions, abattages,
-- avances, cloture_caisse, paiements, mouvements_stock,
-- pos_transactions. CONSTAT HONNETE : les DENTS reelles portent sur
-- les tables CAISSE (ecrites par le VENDEUR). receptions / abattages /
-- avances s'inserent en SESSION MANAGER (validation 0021, module RH) ->
-- le trigger y est un FILET INERTE (le manager garde sa valeur), mais
-- pose quand meme (belt-and-braces + future-proof si un chemin
-- non-manager s'ouvrait). pointages : deja couvert par 0045, EXCLU.
--
-- MECANISME (motif 0045, generalise) : BEFORE INSERT ; si le role JWT
-- est un role REEL non-manager (chef_bande, vendeur, employe, client),
-- la colonne date est ecrasee par la date serveur (current_date pour
-- une colonne 'date', now() pour 'timestamptz' - type resolu a la pose
-- du trigger). MANAGER et contextes SANS JWT (SQL editor / service :
-- role NULL) gardent leur valeur explicite = chemin de correction
-- TRACE (0049 journalise chaque correction). Ecriture generique de la
-- colonne via jsonb_populate_record (nom de colonne dynamique).
--
-- _ops NOTE (raisonnement explicite) : cette migration n'ajoute, ne
-- renomme et ne supprime AUCUNE colonne - triggers purs -> les neuf
-- vues _ops de 0040 restent exactes, AUCUN rejeu section 1. Verifie :
-- rien ici ne touche une colonne des neuf tables.
--
-- FORM : fonction + boucle de pose dynamique dans do $$ (le create
-- policy est le seul rejete par l'editeur - ici pas de policy).
-- Idempotent : create or replace function, drop trigger if exists.
-- Garde par table/colonne (skip + NOTICE si absente). ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans le SQL Editor.
-- Rollback : 0050_rollback.sql (retire les triggers + la fonction).
-- ============================================================

-- ------------------------------------------------------------
-- 1) Fonction trigger generique.
--    TG_ARGV[0] = nom de la colonne date ; TG_ARGV[1] = 'date' | 'ts'.
-- ------------------------------------------------------------
create or replace function public.trg_date_systeme()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role text := auth.jwt() -> 'app_metadata' ->> 'role';
  v_col  text := TG_ARGV[0];
  v_kind text := TG_ARGV[1];
  v_val  jsonb;
begin
  -- Role REEL non-manager uniquement. NULL (SQL editor / service) et
  -- manager gardent leur valeur explicite (correction tracee).
  if v_role is not null and v_role <> 'manager' then
    if v_kind = 'date' then
      v_val := to_jsonb(current_date);
    else
      v_val := to_jsonb(now());
    end if;
    NEW := jsonb_populate_record(NEW, jsonb_set(to_jsonb(NEW), array[v_col], v_val));
  end if;
  return NEW;
end;
$$;

-- ------------------------------------------------------------
-- 2) Pose des triggers (7 tables ; type de colonne resolu a la pose).
--    Table OU colonne absente = NOTICE + skip.
-- ------------------------------------------------------------
do $$
declare
  spec record;
  v_type text;
  v_kind text;
begin
  for spec in
    select * from (values
      ('receptions',       'date_reception'),
      ('abattages',        'date_abattage'),
      ('avances',          'date_avance'),
      ('cloture_caisse',   'date_cloture'),
      ('paiements',        'date_paiement'),
      ('mouvements_stock', 'date_mouvement'),
      ('pos_transactions', 'date_transaction')
    ) as t(tbl, col)
  loop
    if to_regclass(format('public.%I', spec.tbl)) is null then
      raise notice '0050: table % absente - trigger ignore.', spec.tbl;
      continue;
    end if;
    select data_type into v_type
      from information_schema.columns
     where table_schema = 'public' and table_name = spec.tbl
       and column_name = spec.col;
    if v_type is null then
      raise notice '0050: colonne %.% absente - trigger ignore.', spec.tbl, spec.col;
      continue;
    end if;
    v_kind := case when v_type = 'date' then 'date' else 'ts' end;
    execute format('drop trigger if exists aa_date_systeme on public.%I', spec.tbl);
    execute format(
      'create trigger aa_date_systeme before insert on public.%I for each row execute function public.trg_date_systeme(%L, %L)',
      spec.tbl, spec.col, v_kind);
    raise notice '0050: trigger aa_date_systeme pose sur %.% (type %, kind %).', spec.tbl, spec.col, v_type, v_kind;
  end loop;
end $$;

-- ============================================================
-- VERIFICATION (executable - NOTICEs, catalogues en lecture seule)
-- ------------------------------------------------------------
do $$
declare
  r record;
  n integer := 0;
begin
  raise notice '0050 verify: triggers aa_date_systeme poses :';
  for r in
    select c.relname as tbl
      from pg_trigger g
      join pg_class c on c.oid = g.tgrelid
     where g.tgname = 'aa_date_systeme' and not g.tgisinternal
     order by c.relname
  loop
    n := n + 1;
    raise notice '0050 verify:   %', r.tbl;
  end loop;
  raise notice '0050 verify: % trigger(s) au total (attendu : 7 si toutes les tables existent).', n;
  raise notice '0050 verify: NON couverts a dessein - saisies/vaccinations/traitements (hybride front), releves_nuisibles (tournee deliberee), pointages (0045).';
end $$;

-- ------------------------------------------------------------
-- SONDES MANUELLES POST-EXECUTION (Stephen) :
--
-- 1. Console session VENDEUR certifiee (discipline getSession) - une
--    depense de caisse avec une date PASSEE bidon :
--    sb.from('paiements').insert({pdv_id:'<PDV>', montant_fcfa:1000,
--      sens:'depense', statut:'confirme',
--      date_paiement:'2020-01-01T00:00:00Z'}).select()
--    -- attendu : date_paiement revient a AUJOURD'HUI (serveur), pas 2020.
--
-- 2. Meme insert en session MANAGER (avec une date explicite passee,
--    correction legitime) :
--    -- attendu : la date PASSEE est CONSERVEE (chemin de correction).
--    -- puis verifier dans la cloche > Historique (0049) : la ligne
--    -- paiements/INSERT porte la date choisie + l'acteur manager.
--
-- 3. SQL Editor (role postgres, sans JWT) :
--    insert into public.receptions (..., date_reception) values (..., '2020-01-01');
--    -- attendu : 2020-01-01 CONSERVEE (role NULL = non ecrase).
--
-- 4. Non-regression hybride : en session chef, une saisie terrain avec
--    une date d'HIER (bouton Modifier) doit rester HIER en base (aucun
--    trigger sur saisies) et apparaitre datee d'hier dans l'Historique.
-- ============================================================
