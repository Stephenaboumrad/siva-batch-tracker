# Project memory — SIVA Coqorico

## Production deployment

- **Production is Railway only**: `siva-coqorico.com` → CNAME → Railway project `railway-hikari`.
- Railway auto-deploys from `main` on push.
- Railway serves `index.html` statically via `serve .` with `Cache-Control: no-cache`.
- After a merge/push to `main`, **merged does not mean live immediately**: Railway needs a few minutes to rebuild and swap containers before the new build is live. Do **not** test immediately post-merge; wait for Railway to finish deploying.

## Deprecated / obsolete surfaces

- **Ignore GitHub Pages**: `stephenaboumrad.github.io/siva-batch-tracker/` is stale and orphaned.
- That GitHub Pages surface is frozen around June 17 at commit `06cd808`, has `cname:null`, and is **not user-facing**.
- Nothing user-facing points to GitHub Pages. Any old note saying "deployment = GitHub Pages" is wrong and led to a prior misdiagnosis.
- Treat GitHub Pages as deprecated; production = Railway only.

## Supabase / migration operations

- **Merged migration ≠ applied migration**: a migration file merged into the repo is only a file in Git. It is **not** in production until Stephen manually runs it in the Supabase SQL Editor and verifies that the expected object/policy/table/column exists.
- Remember the `0009` incident: do not assume a merged SQL migration exists in Supabase production.
- Claude Code must **never execute SQL against Supabase**.
- Claude Code must **never merge PRs autonomously**.
- Stephen applies SQL manually and verifies `pg_policies` / database objects himself.
