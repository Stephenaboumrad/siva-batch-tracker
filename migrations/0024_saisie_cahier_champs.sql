-- ============================================================
-- Migration 0024 - saisies : champs cahier + une-saisie-par-jour
-- ------------------------------------------------------------
-- Alignement de la saisie journaliere sur le cahier papier tenu par le
-- chef de bande (transcription en fin de journee ou le lendemain matin) :
--   - temperature_observee_c : temperature relevee a la main sur le
--     cahier, DISTINCTE de temperature_c (colonne ambiance destinee au
--     futur pipeline IoT, ajoutee par supabase-setup-v2.sql).
--   - observations : notes libres du cahier.
--   - signes_observes : signes cliniques factuels notes avec la
--     mortalite (abattement, troubles respiratoires, diarrhee, troubles
--     nerveux, boiterie, entassement, texte libre). PAS un diagnostic :
--     le diagnostic reste etabli par le veterinaire via le flux de
--     validation existant, aucune liste de maladies dans l'app.
--   - contrainte saisies_bande_date_uniq UNIQUE (bande_id, date_saisie) :
--     garantie serveur une-saisie-par-jour. Constat PR #104 : AUCUNE
--     garde n'existait (ni client ni base), une double soumission creait
--     une seconde ligne double-comptee par computeIndicators. date_saisie
--     est timestamptz mais l'app ecrit toujours 'YYYY-MM-DD' (minuit
--     UTC), donc l'egalite brute deduplique bien par jour pour les
--     lignes ecrites par l'app. Des NULL multiples ne violent pas une
--     contrainte unique : les lignes historiques sans date restent
--     valides.
--
-- Le front traite la violation d'unicite comme une INFORMATION (meme
-- chemin que l'avertissement doublon consultatif : toast + warn sous le
-- champ date, et retrait de la file hors ligne au rejeu), pas comme une
-- erreur brute - detection sur le nom de contrainte dans le message
-- PostgREST, meme convention que 0022 (paies_employe_mois_uniq).
--
-- STRICTEMENT ADDITIF cote colonnes : 3 colonnes nullables, aucun
-- changement de policy. Les policies RLS 0021 sur saisies sont des
-- predicats de role sans liste de colonnes : les nouvelles colonnes
-- passent automatiquement en SELECT et INSERT pour manager + chef_bande.
-- Le front tente l'ecriture et replie sans ces champs si la base les
-- refuse (repli a l'insertion en ligne + repli au rejeu de la file hors
-- ligne) : l'app reste fonctionnelle AVANT comme APRES cette migration.
--
-- ATTENTION : le bloc do $$ est transactionnel. Si des doublons
-- (bande_id, date_saisie) existent deja, l'ajout de la contrainte echoue
-- et RIEN n'est applique (colonnes comprises). Lancer le PRE-CHECK
-- ci-dessous AVANT, et dedoublonner d'abord le cas echeant.
-- Idempotent : to_regclass + add column if not exists + test
-- pg_constraint avant add constraint.
-- ASCII uniquement, pas de commentaire en fin de ligne d'instruction, pas
-- de point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0024_rollback.sql.
-- ============================================================

-- PRE-CHECK (lecture seule, a lancer AVANT) : doublons existants qui
-- feraient echouer l'ajout de la contrainte. Attendu : 0 ligne. Si des
-- lignes sortent, dedoublonner manuellement (garder la ligne la plus
-- recente par created_at, supprimer les autres) avant d'appliquer la
-- migration.
--   select bande_id, date_saisie, count(*)
--     from public.saisies
--    where date_saisie is not null
--    group by bande_id, date_saisie
--   having count(*) > 1;

do $$
begin
  if to_regclass('public.saisies') is null then
    raise notice '0024: table saisies absente - migration ignoree.';
    return;
  end if;

  alter table public.saisies
    add column if not exists temperature_observee_c numeric;
  alter table public.saisies
    add column if not exists observations text;
  alter table public.saisies
    add column if not exists signes_observes text;

  if not exists (
    select 1
      from pg_constraint
     where conname  = 'saisies_bande_date_uniq'
       and conrelid = 'public.saisies'::regclass
  ) then
    alter table public.saisies
      add constraint saisies_bande_date_uniq unique (bande_id, date_saisie);
  end if;
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
--   select column_name, data_type, is_nullable
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'saisies'
--      and column_name in ('temperature_observee_c', 'observations', 'signes_observes')
--    order by column_name;
--   -- attendu : 3 lignes, is_nullable = YES partout.
--
--   select conname, pg_get_constraintdef(oid)
--     from pg_constraint
--    where conrelid = 'public.saisies'::regclass
--      and conname  = 'saisies_bande_date_uniq';
--   -- attendu : 1 ligne
--   --   saisies_bande_date_uniq | UNIQUE (bande_id, date_saisie)
-- ============================================================
