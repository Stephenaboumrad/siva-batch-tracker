-- ============================================================
-- Migration 0037 - Cloture elargie (POS-1 item 3) : instantane par
--                  mode + fond de caisse verrouille
-- ------------------------------------------------------------
-- La cloture n'attestait que les especes. Six colonnes ADDITIVES sur
-- cloture_caisse :
--
--   total_mm_fcfa         instantane : encaissements mobile money
--                         confirmes depuis la cloture precedente
--   total_credit_fcfa     instantane : credit consenti sur la periode
--                         (ventes finalisees - encaissements lies)
--   total_depenses_fcfa   instantane : depenses caisse de la periode
--   total_versements_fcfa instantane : versements ferme de la periode
--   fond_suivant_fcfa     OVERRIDE manager du fond d'ouverture de la
--                         periode suivante (null = pas d'override, la
--                         caisse calcule compte_fcfa - versements)
--   fond_suivant_note     note OBLIGATOIRE cote UI quand le manager
--                         pose un override (audit de la correction)
--
-- Les instantanes sont DERIVABLES de paiements/pos_transactions : leur
-- valeur ici est d'ACTE SIGNE - ce que la vendeuse a atteste au moment
-- de clore, fige meme si les lignes sous-jacentes bougent ensuite.
--
-- Verrou du fond (amendement approuve) : le vendeur ne saisit plus le
-- fond (lecture seule cote caisse, calcule) ; seul un manager peut le
-- corriger via fond_suivant_fcfa. Le verrou est REEL cote RLS : 0027 ne
-- donne au vendeur qu'INSERT+SELECT sur cloture_caisse - aucun UPDATE.
-- Un vendeur pourrait inserer une cloture avec fond_suivant_fcfa via la
-- console (pas de garde par colonne sur INSERT) : trace auditable,
-- meme niveau de confiance que le reste du schema.
--
-- Anciennes lignes : colonnes a NULL (= instantane inconnu), aucun
-- backfill - un 0 signifierait "atteste a zero", ce qui serait faux.
--
-- Idempotent : to_regclass + add column if not exists. ASCII uniquement,
-- pas de commentaire en fin de ligne d'instruction. Aucune politique
-- RLS modifiee. A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- Rollback : 0037_rollback.sql.
-- ============================================================

do $$
begin
  if to_regclass('public.cloture_caisse') is null then
    raise notice '0037: table cloture_caisse absente (0027 non appliquee) - migration ignoree.';
    return;
  end if;

  alter table public.cloture_caisse add column if not exists total_mm_fcfa         numeric;
  alter table public.cloture_caisse add column if not exists total_credit_fcfa     numeric;
  alter table public.cloture_caisse add column if not exists total_depenses_fcfa   numeric;
  alter table public.cloture_caisse add column if not exists total_versements_fcfa numeric;
  alter table public.cloture_caisse add column if not exists fond_suivant_fcfa     numeric;
  alter table public.cloture_caisse add column if not exists fond_suivant_note     text;

  raise notice '0037: colonnes d instantane et de fond ajoutees a cloture_caisse.';
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- 1. Les 6 colonnes sont presentes (attendu : 6 lignes) :
--   select column_name, data_type from information_schema.columns
--    where table_schema = 'public'
--      and table_name = 'cloture_caisse'
--      and column_name in ('total_mm_fcfa', 'total_credit_fcfa',
--                          'total_depenses_fcfa', 'total_versements_fcfa',
--                          'fond_suivant_fcfa', 'fond_suivant_note')
--    order by column_name;
--
-- 2. Les anciennes lignes restent lisibles, instantanes a NULL
--    (attendu : aucune erreur, valeurs null sur les lignes anterieures) :
--   select cloture_id, compte_fcfa, total_mm_fcfa, fond_suivant_fcfa
--     from cloture_caisse
--    order by date_cloture desc
--    limit 5;
--
-- 3. Politiques inchangees (attendu : 3 lignes rls27_cloture_*) :
--   select policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename = 'cloture_caisse'
--    order by policyname;
-- ============================================================
