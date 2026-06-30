-- ============================================================
-- Migration 0016 - Trace override delai d'attente sur abattages
-- ------------------------------------------------------------
-- Tier-1 socle veterinaire / securite sanitaire, PIECE 1 (suite). Quand un
-- abattage est confirme MALGRE un delai d'attente non respecte (decision
-- reservee a un gerant/manager), on trace la decision sur l'enregistrement
-- d'abattage : qui a confirme, quand, et un motif fige lisible (date autorisee
-- + traitement en cause + delai). Le motif est un INSTANTANE textuel : il reste
-- vrai meme si l'intrant source est ensuite modifie ou supprime (audit DSV /
-- question client).
--
-- STRICTEMENT ADDITIF : 4 colonnes nullable / default false sur abattages.
-- Aucune colonne existante supprimee ni renommee. Ne touche NI le rendement, NI
-- les couts d'abattage, NI la marge / le FCR / la tresorerie. Defaut false /
-- NULL -> les lignes existantes ne portent aucun override.
--
-- Idempotent : to_regclass + add column if not exists. ASCII uniquement, pas de
-- commentaire en fin de ligne d'instruction, pas de point-virgule en commentaire.
-- NO-OP pour l'app tant que le front (PR-4) n'ecrit pas ces colonnes.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor. Rollback : 0016_rollback.sql.
-- ============================================================

do $$
begin
  if to_regclass('public.abattages') is null then
    raise notice '0016: table abattages absente - migration ignoree.';
    return;
  end if;

  alter table public.abattages
    add column if not exists delai_attente_override boolean not null default false;
  alter table public.abattages
    add column if not exists delai_attente_override_par text;
  alter table public.abattages
    add column if not exists delai_attente_override_at timestamptz;
  alter table public.abattages
    add column if not exists delai_attente_override_motif text;
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule) : les 4 colonnes existent.
-- ------------------------------------------------------------
--   select column_name, data_type, is_nullable
--     from information_schema.columns
--    where table_schema = 'public' and table_name = 'abattages'
--      and column_name like 'delai_attente_override%'
--    order by column_name;
--   -- attendu : 4 lignes
--   --   delai_attente_override        | boolean                     | NO
--   --   delai_attente_override_at     | timestamp with time zone    | YES
--   --   delai_attente_override_motif  | text                        | YES
--   --   delai_attente_override_par    | text                        | YES
-- ============================================================
