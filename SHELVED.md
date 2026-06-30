# ExamGuard — SHELVED (not in use)

**Status as of 2026-06-30:** disconnected from the shared Supabase project
`fpwbvtoqabaiisqugqwi` (which also serves sentinel-ra). Not in active use. The
code is kept intact in this folder so it can be redeployed later on its own
backend.

## Why
The shared free-tier Supabase project blew its egress quota and was restricted.
ExamGuard was a second tenant on it. Rather than keep it attached while it's
unused, it's been fully decoupled so the shared project is sentinel-ra's alone.

## What was changed (local, reversible)
- `js/config.js` → `supabaseUrl` and `supabaseAnonKey` set to `''`.
  With both blank, the app runs in **LOCAL FILE mode** (export/import package
  files, grade locally) and connects to **no backend**. See the gate at
  `index.html` (`enabled = !!(cfg.supabaseUrl && cfg.supabaseAnonKey)`).

The previous shared values (now removed) were:
- URL: `https://fpwbvtoqabaiisqugqwi.supabase.co`
- anon key: the `anon`/public JWT for ref `fpwbvtoqabaiisqugqwi` (recoverable
  from git history; do **not** reuse — give ExamGuard its own project).

## Still to do to remove ExamGuard *totally* from the shared project

These are outward / destructive and were left for you to run deliberately:

### 1. Neutralize the live site (exams.dit.edu.gh)
The live site is GitHub Pages from `NiiKpakpoe/exam-guard@main`. Until the
blanked `js/config.js` is pushed (or Pages is disabled), visitors to that URL
still connect to the shared project. Choose one:
- **Push the blanked config** — site stays up but in offline file mode, no
  backend. (`git commit -am "Shelve ExamGuard: run local-file mode, no backend" && git push`)
- **Take Pages down** — repo → Settings → Pages → set source to None (and
  optionally remove the `CNAME` / `exams.dit.edu.gh` DNS record). Cleanest while
  unused.

### 2. (Optional) Back up exam data before dropping it
The shared project is currently *restricted*, so do this only **after service is
restored**. Dumps ExamGuard's data so a future redeploy can reload it:
```bash
OLD_DB='postgresql://postgres.fpwbvtoqabaiisqugqwi:<DB_PASSWORD>@aws-0-<region>.pooler.supabase.com:5432/postgres'
pg_dump "$OLD_DB" --data-only --no-owner --no-privileges \
  --table=public.eg_exams --table=public.eg_results \
  --file=examguard-data-backup-2026-06-30.sql
```
Keep `examguard-data-backup-*.sql` in this folder. (Skip if there's no exam
data worth keeping.)

### 3. Drop ExamGuard's objects from the shared project
Removes the footprint entirely. sentinel-ra uses *different* tables, so this is
safe for it. Run on the **shared (OLD)** project only:
```sql
drop trigger if exists eg_results_notify on public.eg_results;
drop function if exists public.eg_notify_result();
drop function if exists public.eg_fetch_results(text);
drop function if exists public.eg_fetch_exam(text);
drop function if exists public.eg_submit_attempt(text, text, text, jsonb, jsonb);
drop table if exists public.eg_results;
drop table if exists public.eg_exams;
drop table if exists public.eg_secrets;
-- leave eg_touch() if any sentinel-ra trigger uses it; otherwise:
-- drop function if exists public.eg_touch();
```

## How to bring ExamGuard back later
The structure is fully reproducible from this folder — no rewrite needed:
1. Create a **dedicated** Supabase project (see `supabase/MIGRATION-RUNBOOK.md`,
   section 0 — you're capped at 2 free projects, so this likely means Pro).
2. Run `supabase/schema.sql` then `supabase/email-notifications.sql` (edit the
   Resend key first) in the new project's SQL editor.
3. If you kept a data backup, restore it (runbook step 4).
4. Put the **new** project's URL + anon key in `js/config.js`.
5. Re-deploy (push to `NiiKpakpoe/exam-guard` or re-enable Pages) and verify
   (runbook step 7).
