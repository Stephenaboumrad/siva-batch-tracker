-- ============================================================
-- Migration 0024 - saisies : champs cahier de batiment
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
-- STRICTEMENT ADDITIF : 3 colonnes nullables, aucune contrainte, aucun
-- changement de policy. Les policies RLS 0021 sur saisies sont des
-- predicats de role sans liste de colonnes : les nouvelles colonnes
-- passent automatiquement en SELECT et INSERT pour manager + chef_bande.
-- Le front tente l'ecriture et replie sans ces champs si la base les
-- refuse (repli a l'insertion en ligne + repli au rejeu de la file hors
-- ligne) : l'app reste fonctionnelle AVANT comme APRES cette migration.
-- Idempotent : to_regclass + add column if not exists.
-- ASCII uniquement, pas de commentaire en fin de ligne d'instruction, pas
-- de point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0024_rollback.sql.
-- ============================================================

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
end $$;

-- ------------------------------------------------------------
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- select column_name, data_type, is_nullable
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'saisies'
--   and column_name in ('temperature_observee_c', 'observations', 'signes_observes')
-- order by column_name;
-- attendu : 3 lignes, is_nullable = YES partout.
