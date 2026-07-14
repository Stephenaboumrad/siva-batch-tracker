-- ============================================================
-- Migration 0036 - pos_transactions.vendeur_id : suppression de la FK
--                  vers employes(employe_id) (panne fatale caisse)
-- ------------------------------------------------------------
-- SYMPTOME (audit live) : toute vente caisse echoue en 409
--   "violates foreign key constraint pos_transactions_vendeur_id_fkey".
--
-- CAUSE : la FK 0002 (vendeur_id references employes(employe_id)) date
-- de l'epoque ou les tables POS etaient dormantes et supposait que
-- vendeur_id porterait une reference paie. Quand 0027 / caisse.html ont
-- active le POS, le front a ecrit le MATRICULE du vendeur connecte
-- (app_metadata.matricule, ex. SIVA-050) - convention coherente avec
-- cloture_caisse.vendeur_id (0027) et mouvements_stock.responsable
-- (0002), tous deux text SANS FK. Or employes.employe_id est genere
-- 'emp-' + uuid() par la page RH : AUCUN matricule SIVA-xxx ne peut
-- satisfaire la FK. Deux systemes d'identite (matricule Auth vs id paie)
-- et une colonne a cheval sur les deux.
--
-- DECISION : supprimer la contrainte. vendeur_id reste text et porte le
-- matricule (tracabilite), aligne sur ses deux colonnes soeurs. La
-- sauvegarde ne doit jamais etre bloquee par la base (meme philosophie
-- que l'absence de CHECK de dates) ; la barriere d'acces reste la RLS
-- 0027 (INSERT vendeur limite a SON pdv). L'alternative (re-cibler la
-- FK vers profiles(matricule) + seeder chaque vendeur) recree la meme
-- panne au prochain compte mal onboarde et couple la paie au POS.
--
-- La suppression est DYNAMIQUE (pg_constraint) : toute FK posee sur la
-- colonne vendeur_id est retiree, quel que soit son nom - le nom par
-- defaut pos_transactions_vendeur_id_fkey est celui observe en prod,
-- mais on ne presume pas.
--
-- Idempotent : to_regclass + boucle pg_constraint (0 contrainte = deja
-- applique, notice). ASCII uniquement, pas de commentaire en fin de
-- ligne d'instruction.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor (role proprietaire).
-- Rollback : 0036_rollback.sql.
-- ============================================================

do $$
declare
  c record;
  n int := 0;
begin
  if to_regclass('public.pos_transactions') is null then
    raise notice '0036: table pos_transactions absente - migration ignoree.';
    return;
  end if;

  for c in
    select con.conname
      from pg_constraint con
      join pg_attribute att
        on att.attrelid = con.conrelid
       and att.attnum = any (con.conkey)
     where con.conrelid = 'public.pos_transactions'::regclass
       and con.contype = 'f'
       and att.attname = 'vendeur_id'
  loop
    execute format('alter table public.pos_transactions drop constraint %I', c.conname);
    raise notice '0036: contrainte % supprimee.', c.conname;
    n := n + 1;
  end loop;

  if n = 0 then
    raise notice '0036: aucune FK sur pos_transactions.vendeur_id - deja applique.';
  end if;
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- 1. Plus aucune FK sur la colonne vendeur_id (attendu : 0 ligne) :
--   select con.conname
--     from pg_constraint con
--     join pg_attribute att
--       on att.attrelid = con.conrelid
--      and att.attnum = any (con.conkey)
--    where con.conrelid = 'public.pos_transactions'::regclass
--      and con.contype = 'f'
--      and att.attname = 'vendeur_id';
--
-- 2. La colonne existe toujours, type text (attendu : 1 ligne, text) :
--   select column_name, data_type from information_schema.columns
--    where table_schema = 'public'
--      and table_name = 'pos_transactions'
--      and column_name = 'vendeur_id';
--
-- 3. Les autres FK de la table sont intactes (attendu : 3 lignes -
--    pdv_id, site_id, client_id) :
--   select con.conname
--     from pg_constraint con
--    where con.conrelid = 'public.pos_transactions'::regclass
--      and con.contype = 'f'
--    order by con.conname;
--
-- 4. Sonde fonctionnelle OPTIONNELLE (ecriture - a lancer en
--    connaissance de cause puis nettoyer) :
--   insert into pos_transactions (transaction_id, vendeur_id, statut)
--   values ('TEST-0036', 'SIVA-050', 'annulee');
--   delete from pos_transactions where transaction_id = 'TEST-0036';
-- ============================================================
