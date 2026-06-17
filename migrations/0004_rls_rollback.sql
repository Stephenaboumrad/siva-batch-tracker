-- ═══════════════════════════════════════════════════════════════════
-- Migration 0004 — ROLLBACK : restaure les politiques PERMISSIVES (état pré-PR 2)
-- ───────────────────────────────────────────────────────────────────
-- À exécuter UNIQUEMENT si 0004_rls_restrictive.sql casse l'app et que vous
-- voulez revenir instantanément à l'état d'avant (tout le monde peut tout faire,
-- y compris anon). RLS reste activée ; les politiques redeviennent using(true).
--
-- NB : restaure une politique permissive unique `for all` par table (équivalent
-- fonctionnel des 4 politiques d'origine « Allow all select/insert/update/delete »
-- — mêmes droits : lecture/écriture pour TOUS les rôles).
--
-- À EXÉCUTER MANUELLEMENT dans le SQL Editor Supabase. Idempotent.
-- ═══════════════════════════════════════════════════════════════════

-- 1) Supprime toutes les politiques (restrictives rls2_*) sur les tables ciblées.
do $$
declare r record;
begin
  for r in
    select policyname, tablename from pg_policies
    where schemaname = 'public' and tablename = any (array[
      'bandes','saisies','intrants','aliments_phases','matieres','formulations_mp',
      'fournisseurs','receptions','inspections','stocks','clients','commandes',
      'lignes_commande','abattages','notifications','employes','paies','depenses_rh',
      'sites','points_de_vente','pos_transactions','lignes_transaction','mouvements_stock','paiements',
      'profiles'
    ])
  loop
    execute format('drop policy if exists %I on public.%I', r.policyname, r.tablename);
  end loop;
end $$;

-- 2) Recrée une politique PERMISSIVE pour TOUS les rôles (anon + authenticated)
--    sur les 24 tables métier/POS — restaure l'accès total d'origine.
do $$
declare t text;
begin
  foreach t in array array[
    'bandes','saisies','intrants','aliments_phases','matieres','formulations_mp',
    'fournisseurs','receptions','inspections','stocks','clients','commandes',
    'lignes_commande','abattages','notifications','employes','paies','depenses_rh',
    'sites','points_de_vente','pos_transactions','lignes_transaction','mouvements_stock','paiements'
  ] loop
    execute format(
      'create policy "Allow all (rollback)" on public.%I for all to public using (true) with check (true)', t);
  end loop;
end $$;

-- 3) profiles : restaure la lecture publique (état migration 0003).
create policy "profiles readable" on public.profiles for select using (true);
