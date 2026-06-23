# ExamGuard — move to its own Supabase project

Goal: split ExamGuard off the shared project (`fpwbvtoqabaiisqugqwi`, also used by
sentinel-ra) onto a **dedicated** Supabase project, so exam-day traffic, egress
limits, backups, and billing are isolated from everything else.

> **Run this only AFTER the egress fix is deployed and you've confirmed egress
> dropped** (Reports → Usage). The move isolates cost; it does not by itself
> reduce it. No urgency — do it as a clean, deliberate cutover.

This is a static app + a single schema, so there is **no code rewrite** — just a
new project, a data copy, and a one-line config change.

---

## 0. Accounts & plan — read this first

**You do NOT need a new GitHub account or a new Supabase account.**

- **GitHub:** unchanged. This is a backend-only move — the repo
  `NiiKpakpoe/exam-guard` and your deploy flow stay exactly as they are; only the
  two values in `js/config.js` change (step 6). A new account would only make
  sense if you were handing ownership to DIT/the school — a different task.
- **Supabase:** create a new **project under your existing login** — *not* a new
  account. One login holds many projects and many organizations; a second
  account just splits billing/management for no benefit.

**The free-tier cap is per OWNER, not per org.** Supabase limits each
account/owner to **2 active free projects total**, across every org they
administer (confirmed by the "Create project" dialog: *"NiiKpakpoe — Limit: 2
free projects"*). You already own two — the shared `fpwbvtoqabaiisqugqwi`
(sentinel-ra + exam-guard) and Marker — so **creating a 3rd free project is
blocked, and spinning up a new free org does NOT help** (the cap follows your
account). Real choices:

| Option | Cost | When |
|---|---|---|
| **New project on Pro** (upgrade the `Exams-guard` org) ⭐ | $25/mo | The only clean path to a dedicated project. It's a school's live exams — the one app worth Pro: 250 GB egress, daily backups, full isolation. Leave sentinel-ra + Marker on the free org. |
| Free a slot (pause/delete a free project) | $0 | Trap. The only freeable ones are the shared project (pausing it kills sentinel-ra + live exams) or Marker — and ExamGuard would then sit on free tier with the same 5.5 GB egress ceiling that caused this. Not viable for the exam app. |
| Don't move | $0 | **Default for now.** If the egress fix got you comfortably under 5.5 GB, keep ExamGuard on the shared project and revisit Pro only when you actually need isolation (more schools / bigger cohorts). |

> Free tier cannot give the exam app a safe home (5.5 GB egress ceiling). So the
> move is effectively **Pro, or stay shared with the egress fix.** Don't commit
> $25/mo under deadline pressure before confirming the free fix wasn't enough.

---

## What's moving (reference)

| Object | Where it's defined | Notes |
|---|---|---|
| Tables `eg_exams`, `eg_results` | `schema.sql` | the data we copy |
| Private table `eg_secrets` | `email-notifications.sql` | re-enter the Resend key by hand |
| Functions `eg_fetch_exam`, `eg_fetch_results`, `eg_submit_attempt`, `eg_touch`, `eg_notify_result` | both SQL files | recreated by re-running the files |
| Triggers `eg_exams_touch`, `eg_results_notify` | both SQL files | recreated by re-running the files |
| Instructor logins | Supabase **Auth** (auth.users) | NOT migrated — re-created by hand (few accounts) |

**Why auth isn't dumped:** instructors are a handful of Supabase Auth users.
Migrating the `auth` schema is fiddly and risky; re-creating 1–few logins in the
new project takes a minute. Exams reference the instructor via
`eg_exams.owner_id → auth.users(id)`; since the read/update policies use
`using(true)`, nulling those stale owner_ids after import costs you nothing —
instructors still see and manage every exam.

---

## 1. Create the new project (Dashboard)

1. https://supabase.com/dashboard → **New project** → name it e.g. `examguard`.
   Pick the **same region** as your users (closest to Ghana, e.g. `eu-west-*`).
2. Save the generated **database password** somewhere safe.
3. Collect these from the new project (you'll need them below):
   - **Project URL** — Settings → API → `Project URL`  → call it `NEW_PROJECT_URL`
   - **anon public key** — Settings → API → `anon` `public` → `NEW_ANON_KEY`
   - **Connection string** — top-bar **Connect** button → **Session pooler** →
     copy the URI (looks like
     `postgresql://postgres.<ref>:<password>@aws-0-<region>.pooler.supabase.com:5432/postgres`)

Do the same **Connect → Session pooler** copy for the OLD project too.

---

## 2. Build the schema on the new project

In the **new** project's SQL Editor, run these two files **in order**:

1. `schema.sql` — paste the whole file, Run. (Creates tables, RLS policies, and
   all functions incl. the new `eg_fetch_results`.)
2. `email-notifications.sql` — **first edit line 28** to your real Resend key
   (`re_…`), confirm `notify_email` on line 29, then paste and Run.
   (Creates `pg_net`, `eg_secrets`, the notify function + trigger.)

At this point the new project is a working, empty ExamGuard backend.

---

## 3. Dump the data from the OLD project

Use a **PostgreSQL 15+ client** (`pg_dump`/`psql`). Check with `pg_dump --version`.
On macOS: `brew install postgresql@16` if needed.

Set the two connection strings as shell vars (paste the real URIs from step 1):

```bash
OLD_DB='postgresql://postgres.fpwbvtoqabaiisqugqwi:<OLD_DB_PASSWORD>@aws-0-<region>.pooler.supabase.com:5432/postgres'
NEW_DB='postgresql://postgres.<NEW_REF>:<NEW_DB_PASSWORD>@aws-0-<region>.pooler.supabase.com:5432/postgres'
```

Dump **only ExamGuard's data** (not schema, not the whole DB — sentinel-ra's
tables stay untouched):

```bash
pg_dump "$OLD_DB" \
  --data-only --no-owner --no-privileges \
  --table=public.eg_exams \
  --table=public.eg_results \
  --file=examguard-data.sql
```

> `eg_secrets` is deliberately excluded — you re-entered the Resend key in step 2.
> If you'd rather copy it too, add `--table=public.eg_secrets`.

Sanity-check the dump isn't empty:

```bash
grep -c "INSERT INTO\|COPY public" examguard-data.sql   # should be > 0
```

---

## 4. Restore into the NEW project

Run the import inside a session that **disables triggers + FK checks**
(`session_replication_role = replica`). This does two important things at once:

- prevents the FK on `owner_id` from rejecting rows whose instructor doesn't
  exist yet in the new project, and
- stops the `eg_results_notify` trigger from firing **hundreds of emails** as
  historical results are inserted.

```bash
psql "$NEW_DB" <<'SQL'
begin;
set session_replication_role = replica;

\i examguard-data.sql

-- null out any owner_id that points to an instructor not (yet) in this project
update public.eg_exams
   set owner_id = null
 where owner_id is not null
   and owner_id not in (select id from auth.users);

set session_replication_role = origin;
commit;
SQL
```

Verify the row counts match the old project:

```bash
psql "$NEW_DB" -c "select 'exams' t, count(*) from public.eg_exams
                   union all select 'results', count(*) from public.eg_results;"
psql "$OLD_DB" -c "select 'exams' t, count(*) from public.eg_exams
                   union all select 'results', count(*) from public.eg_results;"
```

The two outputs should be identical.

---

## 5. Re-create instructor login(s)

In the **new** project: **Authentication → Users → Add user** — create each
instructor with their email + a password (or **Invite**). That's all that's
needed; policies grant every authenticated user full read/manage on exams.

(Optional) to re-attach ownership instead of leaving it null, after the
instructor account exists:

```sql
update public.eg_exams
   set owner_id = (select id from auth.users where email = 'instructor@dit.edu.gh')
 where owner_id is null;
```

---

## 6. Point the app at the new project

Edit `js/config.js`:

```js
window.EG_CONFIG = {
  supabaseUrl: 'https://<NEW_REF>.supabase.co',   // was fpwbvtoqabaiisqugqwi
  supabaseAnonKey: '<NEW_ANON_KEY>'               // the new project's anon/public key
};
```

Then redeploy the static app (commit + push to `NiiKpakpoe/exam-guard`, or upload
to wherever exams.dit.edu.gh is served from).

---

## 7. Verify the cutover (do this before telling anyone)

1. **Student path:** open the live site, join an exam by access code, submit a
   test attempt. Confirm it grades and you get the Resend email.
2. **Instructor path:** sign in with the new login, open the grade tab, pull
   results — the table should look exactly as before (the `eg_fetch_results`
   function must exist in the new project; it does, from step 2).
3. **Reload test:** refresh the student exam page — it should NOT re-download
   (sessionStorage cache from the egress fix), and the new project's
   **Reports → Usage** egress should be tiny.
4. Watch the new project's egress for a day; it should sit well under free-tier
   now that it serves only ExamGuard.

---

## 8. Decommission on the OLD project (OPTIONAL — only after step 7 passes)

Once the new project is confirmed live, ExamGuard's tables on the **old** shared
project are dead weight. sentinel-ra uses *different* tables, so removing the
`eg_*` objects is safe for it. Run on the **OLD** project only:

```sql
-- triggers/functions first, then tables
drop trigger if exists eg_results_notify on public.eg_results;
drop function if exists public.eg_notify_result();
drop function if exists public.eg_fetch_results(text);
drop function if exists public.eg_fetch_exam(text);
drop function if exists public.eg_submit_attempt(text, text, text, jsonb, jsonb);
drop table if exists public.eg_results;
drop table if exists public.eg_exams;
drop table if exists public.eg_secrets;
-- leave eg_touch() if any sentinel-ra table uses it; otherwise:
-- drop function if exists public.eg_touch();
```

> Double-check `eg_touch()` isn't reused by a sentinel-ra trigger before dropping
> it. When unsure, leave it — it's harmless.

This reclaims disk and removes ExamGuard's load from the shared project entirely.

---

## Rollback

If anything in steps 6–7 misbehaves, revert `js/config.js` to the old
`supabaseUrl`/`anonKey` and redeploy — the old project is untouched until step 8,
so you're instantly back to the previous setup. Fix forward, then retry the
cutover.
