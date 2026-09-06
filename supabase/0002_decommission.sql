-- ExamGuard — DECOMMISSION from the shared production project.
--
-- Run this ONCE in the Supabase SQL Editor for project `fpwbvtoqabaiisqugqwi`.
--
-- WHY THIS EXISTS
-- ---------------
-- ExamGuard was retired in 2026 and its client config was blanked, but its
-- database objects were never removed from the shared project (SHELVED.md
-- step 3 was left as a manual action and never run). That project now also
-- carries Sentinel-RA (assessments/intakes), the monitoring hub (mc_*) and
-- Planwright (pw_*).
--
-- Meanwhile ExamGuard's `anon` API key sits in the public git history of
-- github.com/NiiKpakpoe/exam-guard (commits 4a680df and eacf4ad) and remains
-- valid until 2036. Verified live on 2026-09-06: it authenticates, and all
-- three eg_* RPCs execute for role `anon`:
--
--   eg_fetch_exam(text)       -> 200   (intended to be public)
--   eg_fetch_results(text)    -> 200   NOT intended: schema.sql grants it only
--                                      `to authenticated`, but PostgreSQL grants
--                                      EXECUTE to PUBLIC by default and that
--                                      default was never revoked. SECURITY
--                                      DEFINER, so it bypasses RLS entirely.
--   eg_submit_attempt(...)    -> 400 exam_not_found (i.e. it RAN) — an
--                                      unauthenticated INSERT path into the
--                                      production database.
--
-- eg_exams and eg_results are currently empty, so nothing is leaking today.
-- This removes the latent read path and the anonymous write path for good.
--
-- SAFETY
-- ------
-- Verified 2026-09-06: no other tenant references any eg_* object. Sentinel-RA
-- uses its own public.touch_updated_at(); the mc_* and pw_* schemas do not
-- reference eg_*. Functions are dropped WITHOUT CASCADE so that if anything
-- unexpectedly depends on one, PostgreSQL refuses rather than silently
-- removing it — the DO block reports that instead of failing the whole run.

begin;

-- 1. Triggers first (explicit; the table drops below would also remove them).
drop trigger if exists eg_results_notify on public.eg_results;
drop trigger if exists eg_exams_touch    on public.eg_exams;

-- 2. Tables. CASCADE here only reaches ExamGuard's own dependent objects.
drop table if exists public.eg_results cascade;
drop table if exists public.eg_exams   cascade;
drop table if exists public.eg_secrets cascade;

-- 3. Every remaining public.eg_* function, whatever its signature.
--    Signature-drift-proof: reads real signatures out of the catalog rather
--    than trusting the ones written in schema.sql (eg_fetch_results was
--    rewritten in commit 9b03dff).
do $$
declare
  r        record;
  n_ok     int := 0;
  n_held   int := 0;
begin
  for r in
    select p.oid::regprocedure as sig
      from pg_proc p
      join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public'
       and p.proname like 'eg\_%'
  loop
    begin
      execute format('drop function %s', r.sig);   -- no CASCADE, deliberately
      n_ok := n_ok + 1;
      raise notice 'dropped %', r.sig;
    exception when dependent_objects_still_exist then
      n_held := n_held + 1;
      raise warning 'KEPT % — something still depends on it; investigate before removing', r.sig;
    end;
  end loop;
  raise notice 'eg_* functions dropped: %, kept due to dependencies: %', n_ok, n_held;
end $$;

commit;

-- 4. Verification — both queries must return zero rows.
select p.oid::regprocedure as leftover_function
  from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
 where ns.nspname = 'public' and p.proname like 'eg\_%';

select tablename as leftover_table
  from pg_tables
 where schemaname = 'public' and tablename like 'eg\_%';
