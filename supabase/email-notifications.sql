-- ===========================================================================
--  ExamGuard — OPTIONAL email notifications (Resend, no server to deploy)
--  -------------------------------------------------------------------------
--  Emails the instructor when a student submits. Uses Supabase's pg_net
--  extension to POST directly to the Resend API from a database trigger.
--
--  Run this ONLY when you want email alerts. Steps:
--    1. Create a free account at https://resend.com and an API key.
--    2. (Recommended) Verify a sending domain in Resend. For a quick test you
--       can send FROM 'onboarding@resend.dev' without verifying anything.
--    3. Edit the two values in the eg_secrets inserts below, then run this file
--       in the Supabase SQL Editor.
--    4. To switch to "flagged submissions only", see the WHEN clause note near
--       the bottom.
-- ===========================================================================

create extension if not exists pg_net;

-- private settings table (no RLS policies -> unreachable by anon/clients) -----
create table if not exists public.eg_secrets (
  key   text primary key,
  value text not null
);
alter table public.eg_secrets enable row level security;  -- deny-all by default

-- >>> EDIT THESE TWO LINES <<< -----------------------------------------------
insert into public.eg_secrets (key, value) values
  ('resend_api_key', 're_REPLACE_WITH_YOUR_KEY'),
  ('notify_email',   'alex.acquaye@gmail.com')
on conflict (key) do update set value = excluded.value;
-- Optional: set a verified from-address; defaults to Resend's test sender.
insert into public.eg_secrets (key, value) values
  ('from_email', 'ExamGuard <onboarding@resend.dev>')
on conflict (key) do update set value = excluded.value;

-- trigger: POST an email to Resend on each new result -------------------------
create or replace function public.eg_notify_result()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  api_key text;
  to_addr text;
  from_addr text;
  subj text;
  body text;
begin
  select value into api_key   from public.eg_secrets where key = 'resend_api_key';
  select value into to_addr   from public.eg_secrets where key = 'notify_email';
  select value into from_addr from public.eg_secrets where key = 'from_email';
  if api_key is null or to_addr is null then return new; end if;

  subj := format('[ExamGuard] %s — %s scored %s%% (%s)',
            (select title from public.eg_exams where id = new.exam_id),
            coalesce(new.name, new.student_id),
            new.percent,
            case when new.passed then 'PASS' else 'FAIL' end);

  body := format(
    '<h2>New exam submission</h2>
     <p><b>Student:</b> %s (%s)<br>
        <b>Score:</b> %s / %s (%s%%) — <b>%s</b><br>
        <b>Integrity flags:</b> %s<br>
        <b>Submitted:</b> %s</p>
     <p>Open the ExamGuard grade tab to review the full integrity log.</p>',
    coalesce(new.name,''), new.student_id, new.score, new.total, new.percent,
    case when new.passed then 'PASS' else 'FAIL' end,
    new.violations, new.submitted_at);

  perform net.http_post(
    url     := 'https://api.resend.com/emails',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || api_key,
                 'Content-Type',  'application/json'),
    body    := jsonb_build_object(
                 'from', coalesce(from_addr, 'onboarding@resend.dev'),
                 'to',   to_addr,
                 'subject', subj,
                 'html', body)
  );
  return new;
end;
$$;

drop trigger if exists eg_results_notify on public.eg_results;
create trigger eg_results_notify
  after insert on public.eg_results
  for each row execute function public.eg_notify_result();

-- ---------------------------------------------------------------------------
-- FLAGGED-ONLY variant: replace the trigger above with this to email only when
-- a submission has integrity violations:
--
--   create trigger eg_results_notify
--     after insert on public.eg_results
--     for each row when (new.violations > 0)
--     execute function public.eg_notify_result();
-- ---------------------------------------------------------------------------
