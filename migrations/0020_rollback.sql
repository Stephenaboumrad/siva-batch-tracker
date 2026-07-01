-- ============================================================
-- Rollback 0020 - Seed du programme previsionnel type "ferme"
-- ------------------------------------------------------------
-- Retire UNIQUEMENT les lignes seedees (id metier prefixe 'pv-ferme-%' /
-- 'pt-ferme-%'). Ne touche NI les lignes ajoutees manuellement, NI les
-- executions par bande (vaccinations / traitements) : les FK sont en
-- "on delete set null" (traitements.proto_trait_id) -> les actes deja realises
-- restent, detaches du plan. Idempotent. ASCII uniquement.
-- A EXECUTER MANUELLEMENT dans Supabase SQL Editor.
-- ============================================================

do $$
begin
  if to_regclass('public.protocole_vaccinal') is not null then
    delete from public.protocole_vaccinal where proto_id like 'pv-ferme-%';
  end if;
  if to_regclass('public.protocole_traitements') is not null then
    delete from public.protocole_traitements where proto_trait_id like 'pt-ferme-%';
  end if;
end $$;
