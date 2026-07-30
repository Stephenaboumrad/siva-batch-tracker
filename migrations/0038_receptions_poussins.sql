-- ============================================================
-- Migration 0038 - receptions : detail reception poussins (SC-1.1)
-- ------------------------------------------------------------
-- Trois colonnes ADDITIVES sur receptions, renseignees quand
-- categorie = 'poussin'. Nullable partout : aucune autre categorie
-- n'est touchee, aucune ligne existante modifiee.
--
--   effectif_commande    int      poussins COMMANDES au couvoir
--   mortalite_transport  int      morts constates a l'arrivee (DOA)
--   poids_moyen_g        numeric  poids moyen d'arrivee (g)
--
-- CONVENTION (front, SC-1.1) : receptions.quantite reste l'effectif
-- RECU VIVANT (mis en place) - c'est lui qui pre-remplit
-- bandes.nb_poussins_entree a la creation de bande depuis la
-- reception. Aucune contrainte arithmetique entre commande / recu /
-- mortalite : la base ne bloque jamais une sauvegarde (discipline
-- maison) - les ecarts se lisent, ils ne s'imposent pas.
--
-- Aucune politique RLS modifiee : receptions reste SELECT roles
-- internes / ecritures manager (0021), le chemin chef passe par la
-- boucle notifications.
--
-- Idempotent : to_regclass + add column if not exists. ASCII
-- uniquement, pas de commentaire en fin de ligne d'instruction.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- Rollback : 0038_rollback.sql.
-- ============================================================

do $$
begin
  if to_regclass('public.receptions') is null then
    raise notice '0038: table receptions absente - migration ignoree.';
    return;
  end if;

  alter table public.receptions add column if not exists effectif_commande   int;
  alter table public.receptions add column if not exists mortalite_transport int;
  alter table public.receptions add column if not exists poids_moyen_g       numeric;

  raise notice '0038: colonnes de detail poussins ajoutees a receptions.';
end $$;

-- ============================================================
-- VERIFICATION (a lancer APRES, en lecture seule)
-- ------------------------------------------------------------
-- 1. Les 3 colonnes sont presentes, types attendus (attendu : 3 lignes,
--    integer / integer / numeric) :
--   select column_name, data_type from information_schema.columns
--    where table_schema = 'public'
--      and table_name = 'receptions'
--      and column_name in ('effectif_commande', 'mortalite_transport', 'poids_moyen_g')
--    order by column_name;
--
-- 2. Les lignes existantes restent lisibles, nouvelles colonnes a NULL
--    (attendu : aucune erreur, valeurs null partout) :
--   select reception_id, categorie, quantite,
--          effectif_commande, mortalite_transport, poids_moyen_g
--     from receptions
--    order by date_reception desc
--    limit 5;
--
-- 3. Politiques inchangees (attendu : rls21_receptions_select +
--    rls21_receptions_write, rien d'autre) :
--   select policyname, cmd from pg_policies
--    where schemaname = 'public' and tablename = 'receptions'
--    order by policyname;
-- ============================================================
