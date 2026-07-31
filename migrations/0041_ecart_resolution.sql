-- ============================================================
-- Migration 0041 - cloture_caisse : resolution d'ecart (UX lot C, C1)
-- ------------------------------------------------------------
-- Un ecart de cloture restait « non resolu » pour toujours : le badge et
-- les agregats d'ecarts n'avaient aucun moyen de s'eteindre apres
-- verification par le gerant. Trois colonnes ADDITIVES, nullable :
--
--   ecart_resolu_note  text         note OBLIGATOIRE cote UI (audit :
--                                    « recompte le [date], erreur de
--                                    comptage »...)
--   ecart_resolu_at    timestamptz  horodatage de la resolution
--   ecart_resolu_par   text         matricule du manager
--
-- Convention front : ecart NON RESOLU = ecart_fcfa <> 0 ET
-- ecart_resolu_at IS NULL. Les lignes resolues sortent des agregats
-- (badge onglet, carte zone 1, bandeau) mais restent visibles dans le
-- tableau des clotures avec un tag « resolu ».
--
-- Aucune politique RLS modifiee : l'UPDATE passe par rls27_cloture_manager
-- (0027, FOR ALL manager) - le vendeur n'a toujours aucun UPDATE, il ne
-- peut pas s'auto-resoudre un ecart.
--
-- NB : cloture_caisse n'est PAS dans les 9 tables sous vue _ops (0040) -
-- aucun rejeu de bloc de vues requis (regle CLAUDE.md verifiee).
--
-- Anciennes lignes : colonnes a NULL (= non resolu), aucun backfill.
-- Idempotent : to_regclass + add column if not exists. ASCII uniquement,
-- pas de commentaire en fin de ligne d'instruction.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- Rollback : 0041_rollback.sql.
-- ============================================================

do $$
begin
  if to_regclass('public.cloture_caisse') is null then
    raise notice '0041: table cloture_caisse absente (0027 non appliquee) - migration ignoree.';
    return;
  end if;

  alter table public.cloture_caisse add column if not exists ecart_resolu_note text;
  alter table public.cloture_caisse add column if not exists ecart_resolu_at   timestamptz;
  alter table public.cloture_caisse add column if not exists ecart_resolu_par  text;

  raise notice '0041: colonnes de resolution d ecart ajoutees a cloture_caisse.';
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- 1. Les 3 colonnes sont presentes (attendu : 3 lignes) :
--   select column_name, data_type from information_schema.columns
--    where table_schema = 'public'
--      and table_name = 'cloture_caisse'
--      and column_name in ('ecart_resolu_note', 'ecart_resolu_at', 'ecart_resolu_par')
--    order by column_name;
--
-- 2. Anciennes lignes lisibles, colonnes a NULL (attendu : aucune erreur) :
--   select cloture_id, ecart_fcfa, ecart_resolu_note, ecart_resolu_at
--     from cloture_caisse
--    order by date_cloture desc
--    limit 5;
--
-- 3. Politiques inchangees (attendu : 3 lignes rls27_cloture_*) :
--   select policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename = 'cloture_caisse'
--    order by policyname;
--
-- 4. Test DENY vendeur (simulation JWT - le vendeur ne peut pas
--    s'auto-resoudre, attendu : 0 ligne affectee) :
--   begin;
--     set local role authenticated;
--     set local request.jwt.claims =
--       '{"role":"authenticated","app_metadata":{"role":"vendeur","point_de_vente_id":"pdv-bingerville"}}';
--     update cloture_caisse set ecart_resolu_note = 'test'
--      where ecart_fcfa <> 0;
--   rollback;
-- ============================================================
