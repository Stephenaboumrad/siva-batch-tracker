-- ═══════════════════════════════════════════════════════════════════
-- Migration 0003 — Authentification : table `profiles` (mapping matricule → rôle)
-- ───────────────────────────────────────────────────────────────────
-- Contexte : Security PR 1 remplace le login cosmétique (mots de passe en clair
-- dans index.html) par Supabase Auth. Le rôle (manager / chef_bande) n'est plus
-- codé en dur côté client ; il est dérivé de l'utilisateur authentifié :
--   1) en priorité depuis app_metadata du JWT (claims `role` / `matricule` / `name`),
--   2) à défaut depuis cette table `profiles` (mapping de secours auditable).
--
-- À EXÉCUTER MANUELLEMENT (SQL Editor Supabase). Cette migration :
--   • ne crée AUCUN compte Auth (réservé au dashboard / Admin API — voir étapes
--     manuelles dans la description de la PR),
--   • n'écrit aucune donnée métier,
--   • ne modifie AUCUNE politique RLS existante (PR 2 s'en charge).
-- Idempotente : ré-exécutable sans erreur.
-- ═══════════════════════════════════════════════════════════════════

create table if not exists profiles (
  matricule   text primary key,
  email       text unique not null,
  name        text not null,
  role        text not null default 'chef_bande'
              check (role in ('manager', 'chef_bande')),
  created_at  timestamptz not null default now()
);

-- RLS : lecture seule pour l'app (clé anon/authenticated). AUCUNE politique
-- d'écriture → toute écriture est refusée par défaut (l'app n'écrit jamais
-- profiles ; le seeding ci-dessous s'exécute en tant que propriétaire et
-- contourne RLS). Création d'une politique sur une NOUVELLE table — aucune
-- politique existante n'est modifiée.
alter table profiles enable row level security;
drop policy if exists "profiles readable" on profiles;
create policy "profiles readable" on profiles for select using (true);

-- Mapping matricule → e-mail interne / nom / rôle pour les 3 comptes actuels.
-- (Nom de SIVA-003 conservé tel qu'affiché aujourd'hui — « Démonstration » ;
--  ajustez si vous préférez « Mounir ».)
insert into profiles (matricule, email, name, role) values
  ('SIVA-001', 'siva-001@coqorico.internal', 'Stephen Aboumrad', 'manager'),
  ('SIVA-002', 'siva-002@coqorico.internal', 'Zahreddine Abbas', 'manager'),
  ('SIVA-003', 'siva-003@coqorico.internal', 'Démonstration',    'manager')
on conflict (matricule) do update
  set email = excluded.email,
      name  = excluded.name,
      role  = excluded.role;
