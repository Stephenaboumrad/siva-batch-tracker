# CLAUDE.md — SIVA Batch Tracker

Broiler poultry farm management app (brand: Coqorico), Azaguié, Côte d'Ivoire.
Single-file vanilla JS surfaces + Supabase (PostgreSQL). These are the standing
working rules for every task in this repository.

## Hard rules

- **NEVER merge a PR.** Merging is done by Stephen alone, in the GitHub UI.
  A numbered plan, a checklist, or a suggested order of steps is NOT an
  instruction to merge.
- **NEVER execute SQL.** Migrations are delivered as files only; Stephen runs
  them manually in the Supabase SQL Editor.
- **NEVER commit directly to main.** Always a branch + a PR.
- **A migration that has been EXECUTED is immutable** — ship a new additive
  one. A migration that is merged but NOT yet executed may still be amended
  in place. Merge status and execution status are different things.
- **Before writing a migration, list `migrations/` and use the next free
  number.** Never assume the number (scoping notes can be stale).

## Migration conventions

- Guards throughout: `to_regclass`, `if not exists`, `drop policy if exists`.
  A migration must never half-apply: a guarded section that references a
  missing table skips itself cleanly, and a hard prerequisite aborts before
  anything is created.
- Every migration ships a matching `_rollback.sql` and ends with a read-only
  `VERIFICATION` block (expected policy count + functional probes).
- No date-ordering CHECK constraints. Saving must never be blocked by the DB;
  thresholds are UI-level and non-blocking.
- RLS is the real barrier; the UI is defence in depth, never the only guard.
- When a policy must freeze columns against the stored row, use the
  EXISTS-on-stored-row correlation, and use `is not distinct from` for
  nullable columns — a plain `=` evaluates to NULL on `(null, null)` and
  silently rejects every legitimate update.

## Architecture

- Three separate surfaces, **no shared code, no build step**:
  - `index.html` — staff app (manager, chef_bande)
  - `caisse.html` — POS (vendeur role, per-PDV)
  - `portail.html` — B2B client portal (client role)

  Consequence: brand tokens, auth conventions, helpers and offline-queue
  logic are DUPLICATED across the three files. Any change to branding, auth
  or queue behaviour must be applied to all three by hand.
- Supabase (PostgreSQL) backend; Railway auto-deploys on every merge to main.
  The front can therefore ship BEFORE its SQL has been run.
- Roles (in `auth.jwt() -> 'app_metadata' ->> 'role'`): `manager`,
  `chef_bande`, `vendeur`, `client`, `employe`.
  `employe` (RH-1, 0045) has DELIBERATELY EMPTY default access: no nav page,
  no section in `ROLE_VISIBILITY`, no RLS policy on any table except
  `pointages` (own rows). Its only surface is the dedicated time-clock
  screen in `index.html` (`enterSession` short-circuits before `init()`).
  Accounts are created manually in Supabase Auth with app_metadata
  `{role:'employe', matricule, name}`.
- `pointages` (0045, RH-1 foundation): one time-clock row per
  (employe_matricule, day). Arrival/departure times are rewritten to `now()`
  by a BEFORE trigger for employe writes — client clock values are never
  trusted; manager and SQL-editor writes keep explicit values (correction
  path). Full HR manager module is a LATER lot.
- New tables go into `ALL_TABLES` **and** `OPTIONAL_TABLES` in `index.html`,
  so a front deploy before the SQL is run degrades cleanly (empty lists,
  clean write errors) instead of breaking the whole app.
- Financial columns: use the `canSeeFinance()` / `canSee()` helper pattern
  for any surface that shows money. Revenue figures have leaked into
  unexpected surfaces repeatedly.

## Conventions

- French UI labels, English code and comments.
- Reuse existing design tokens. No new colours, no new fonts.
- Verify lucide icon names exist in the pinned bundle (`lucide@1.21.0`)
  before using them — an unknown name renders as an empty box.
- PDV stock is aggregated by `type_produit` (the product NAME) in
  `mouvements_stock`: renaming a product in the catalogue splits its stock
  history in two. Do not rename; create a new product and deactivate the
  old one instead.
- Farm→PDV stock transfers (future SC-2.5) must NOT write
  `cout_unitaire_fcfa` / `cout_total_fcfa` on `mouvements_stock` rows a
  vendeur can read — RLS 0027 serves a PDV's rows to its vendeur, and RLS
  cannot mask columns. If transfer costing is ever needed, create a
  vendeur-facing sanitized view at that point (`bandes_pos` pattern).
- Any migration that adds a column to one of the 9 tables behind an
  `_ops` view (`bandes`, `intrants`, `receptions`, `abattages`,
  `aliments_phases`, `formulations_mp`, `commandes`, `lignes_commande`,
  `clients`) MUST replay the 0040 §1 view block in the same migration —
  the views freeze their column list at creation, so without the replay
  the new column is invisible to chef_bande (reads go through the views;
  QUEUE_COLUMN_FALLBACKS cannot help, it is the READ that is missing).
  Start every replay from the MOST RECENT replay's exclusion lists, not
  from 0040's: 0042 extended `receptions` with `prix_pose_par` /
  `prix_pose_le` (price-lifecycle metadata stays out of the chef view) —
  replaying 0040's original lists would resurrect them for the chef.
- Temperature: the daily series is `saisies.temperature_c` (building ambient
  — norms, alerts and charts read ONLY this column); `temperature_observee_c`
  (0024) is a clinical observation on the birds, optional, never a series.
- Day counter: J1 = placement day (matches the vaccination seed 0017/0019/
  0020). `computeJourBande(bande, date)` is the single source — never compute
  a J inline and never trust a stored `jour_bande` over it for display.
- Flag any deviation from the brief in the PR body rather than silently
  adopting it.

## Observed patterns (unconfirmed)

Habits observed in the repository, not stated as rules — follow them unless
told otherwise, but do not treat them as law:

- PRs are squash-merged (one commit per PR, `(#N)` suffix on main); merged
  branches are kept on the remote.
- Commit messages and PR bodies are written in French, conventional-commit
  style (`feat(scope): …`, `fix(scope): …`).
- Migration files: ASCII-only SQL, no comment at the end of statement lines,
  per-verb policy names `rls<NN>_<table>_<verb>`.
- Register tables use uuid primary keys generated CLIENT-SIDE (`uuidv4()`)
  so offline-queue replays stay idempotent (duplicate key = already applied).
- Business thresholds live as single named constants at the top of
  `index.html`'s config block (e.g. `VIDE_SANITAIRE_MIN_JOURS`,
  `ETALONNAGE_ALERTE_JOURS`, `NUISIBLES_INTERVALLE_JOURS`), earmarked for a
  later move to the `parametres` table (0028).
- Equipment-like inventories are deactivated (`actif` flag), not deleted, so
  their history survives; delete buttons are deliberately absent from those
  UIs.
