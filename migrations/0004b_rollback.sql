-- ═══════════════════════════════════════════════════════════════════
-- Migration 0004b — ROLLBACK : restaure l'état PERMISSIF (pré-PR 2)
-- ───────────────────────────────────────────────────────────────────
-- À exécuter UNIQUEMENT pour revenir en arrière (tout le monde peut tout faire,
-- y compris anon). RLS reste activée ; les politiques redeviennent using(true)
-- pour le rôle public.
--
-- Robuste (ignore les tables absentes) et idempotent. Pour chaque table présente :
-- DROP de toutes ses politiques (les rls2_* restrictives), puis CREATE d'une
-- politique permissive `for all to public using(true)` — équivalent fonctionnel
-- des 4 « Allow all … » d'origine (lecture/écriture pour TOUS les rôles).
-- profiles : lecture publique restaurée (état migration 0003).
--
-- À EXÉCUTER MANUELLEMENT (SQL Editor Supabase).
-- ═══════════════════════════════════════════════════════════════════

do $$
declare
  t  text;
  p  record;
  all_business text[] := array[
    'bandes','saisies','intrants','aliments_phases','matieres','formulations_mp',
    'fournisseurs','receptions','inspections','stocks','clients','commandes',
    'lignes_commande','abattages','notifications','employes','paies','depenses_rh',
    'sites','points_de_vente','pos_transactions','lignes_transaction','mouvements_stock','paiements'
  ];
begin
  foreach t in array all_business loop
    if to_regclass(format('public.%I', t)) is not null then
      execute format('alter table public.%I enable row level security', t);
      for p in select policyname from pg_policies where schemaname='public' and tablename=t loop
        execute format('drop policy if exists %I on public.%I', p.policyname, t);
      end loop;
      execute format(
        'create policy "Allow all (rollback)" on public.%I for all to public using (true) with check (true)', t);
    end if;
  end loop;

  if to_regclass('public.profiles') is not null then
    execute 'alter table public.profiles enable row level security';
    for p in select policyname from pg_policies where schemaname='public' and tablename='profiles' loop
      execute format('drop policy if exists %I on public.profiles', p.policyname);
    end loop;
    execute 'create policy "profiles readable" on public.profiles for select using (true)';
  end if;
end $$;
