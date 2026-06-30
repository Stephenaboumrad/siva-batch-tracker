-- ============================================================
-- Migration 0015 - Delai d'attente avant abattage (withdrawal period)
-- ------------------------------------------------------------
-- Tier-1 socle veterinaire / securite sanitaire, PIECE 1. Ajoute le delai
-- d'attente (en jours) par enregistrement intrant, saisi par l'eleveur depuis
-- l'etiquette produit / le veto / la DSV. Permet de calculer cote app la date
-- d'abattage au plus tot par bande = max(date_intrant + delai_attente_jours)
-- et d'avertir si une session d'abattage est datee avant cette date.
--
-- FRAMEWORK CONFIGURABLE : aucune valeur medicale codee en dur. La colonne ne
-- stocke QUE le nombre saisi par l'utilisateur. Defaut NULL = aucun delai
-- enregistre -> les lignes existantes ne declenchent aucun avertissement.
--
-- STRICTEMENT ADDITIF : aucune colonne existante supprimee ni renommee. Ne
-- touche NI le calcul FCR/IC, NI la marge / le cout de revient, NI la
-- tresorerie. Couche de securite uniquement. Aucune vue, aucune RPC, aucun
-- backfill. NO-OP pour l'app tant que le front (PR-2) n'ecrit pas la colonne :
-- l'app lit en select('*') (la nouvelle colonne apparait, vide) et n'envoie
-- pas encore delai_attente_jours.
--
-- Idempotent : to_regclass + add column if not exists + garde pg_constraint.
-- ASCII uniquement, pas de commentaire en fin de ligne d'instruction, pas de
-- point-virgule en commentaire.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0015_rollback.sql.
-- ============================================================

do $$
begin
  if to_regclass('public.intrants') is null then
    raise notice '0015: table intrants absente - migration ignoree.';
    return;
  end if;

  alter table public.intrants
    add column if not exists delai_attente_jours int;

  if not exists (
    select 1 from pg_constraint
    where conname = 'intrants_delai_attente_jours_chk'
      and conrelid = 'public.intrants'::regclass
  ) then
    alter table public.intrants
      add constraint intrants_delai_attente_jours_chk
      check (delai_attente_jours is null or delai_attente_jours >= 0);
  end if;
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule) : la colonne existe.
-- ------------------------------------------------------------
--   select column_name, data_type, is_nullable
--     from information_schema.columns
--    where table_schema = 'public'
--      and table_name   = 'intrants'
--      and column_name  = 'delai_attente_jours';
--   -- attendu : 1 ligne, data_type = integer, is_nullable = YES.
-- ============================================================
