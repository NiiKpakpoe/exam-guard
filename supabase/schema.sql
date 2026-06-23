-- ===========================================================================
--  ExamGuard — Supabase schema (cloud mode)
--  Paste this whole file into the Supabase SQL Editor and click "Run".
--
--  Security model
--  --------------
--  • Instructors are the authenticated users of THIS project. They publish
--    exams and read results.
--  • Students are anonymous. They NEVER read the eg_exams table directly, so
--    they can never see the correct answers or the pass mark logic. They go
--    through two SECURITY DEFINER functions:
--        eg_fetch_exam(access_code)   -> exam WITHOUT answer keys
--        eg_submit_attempt(...)       -> grades server-side, stores result
--  • Because grading happens in the database against the hidden answer key,
--    a student cannot forge a score, and a single attempt is enforced in SQL.
-- ===========================================================================

-- ---------- exams (answer keys live here; students cannot read this table) --
create table if not exists public.eg_exams (
  id          text primary key,                 -- matches the app's exam id
  owner_id    uuid default auth.uid() references auth.users (id) on delete set null,
  owner_email text,
  title       text,
  access_code text not null,                     -- what students type to join
  config      jsonb not null,                    -- full exam incl. questions + answer keys
  active      boolean not null default true,     -- uncheck to close an exam
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists eg_exams_access_idx on public.eg_exams (access_code);

alter table public.eg_exams enable row level security;

drop policy if exists "exam read auth"   on public.eg_exams;
drop policy if exists "exam insert auth" on public.eg_exams;
drop policy if exists "exam update auth" on public.eg_exams;
drop policy if exists "exam delete auth" on public.eg_exams;

create policy "exam read auth"   on public.eg_exams for select to authenticated using (true);
create policy "exam insert auth" on public.eg_exams for insert to authenticated with check (auth.uid() = owner_id);
create policy "exam update auth" on public.eg_exams for update to authenticated using (true) with check (true);
create policy "exam delete auth" on public.eg_exams for delete to authenticated using (true);
-- NOTE: deliberately NO policy for the anon role -> students cannot read answer keys.

-- ---------- results (students insert only via the RPC below) ----------------
create table if not exists public.eg_results (
  id           uuid primary key default gen_random_uuid(),
  exam_id      text not null references public.eg_exams (id) on delete cascade,
  student_id   text not null,
  name         text,
  score        int,
  total        int,
  percent      int,
  passed       boolean,
  violations   int not null default 0,
  data         jsonb not null,                   -- full submission (answers, log, meta, webcam)
  submitted_at timestamptz not null default now()
);
-- one attempt per student id per exam
create unique index if not exists eg_results_attempt
  on public.eg_results (exam_id, lower(student_id));

alter table public.eg_results enable row level security;

drop policy if exists "result read auth" on public.eg_results;
create policy "result read auth" on public.eg_results for select to authenticated using (true);
-- NOTE: no insert/update/delete policy -> all writes go through eg_submit_attempt (SECURITY DEFINER).

-- ---------- keep updated_at honest -----------------------------------------
create or replace function public.eg_touch() returns trigger as $$
begin new.updated_at = now(); return new; end;
$$ language plpgsql;

drop trigger if exists eg_exams_touch on public.eg_exams;
create trigger eg_exams_touch before update on public.eg_exams
  for each row execute function public.eg_touch();

-- ===========================================================================
--  FUNCTION 1 — fetch a sanitized exam by access code (answers stripped out)
-- ===========================================================================
create or replace function public.eg_fetch_exam(p_access_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  ex   public.eg_exams;
  pub  jsonb;
begin
  select * into ex
    from public.eg_exams
   where access_code = p_access_code and active = true
   order by updated_at desc
   limit 1;
  if not found then return null; end if;

  pub := ex.config;
  -- strip the signing salt and the correct/answers keys from every question
  pub := pub - 'salt';
  pub := jsonb_set(pub, '{questions}', (
    select coalesce(jsonb_agg(q - 'correct' - 'answers'), '[]'::jsonb)
      from jsonb_array_elements(ex.config -> 'questions') q
  ));
  pub := jsonb_set(pub, '{id}', to_jsonb(ex.id));
  return pub;
end;
$$;
grant execute on function public.eg_fetch_exam(text) to anon, authenticated;

-- ===========================================================================
--  FUNCTION 1b — fetch results for an exam WITHOUT the heavy payload.
--  The instructor results table only needs scalars + the violation log + a
--  "was a webcam photo captured" flag. The base64 webcam photo (and the raw
--  answers) live in data.* and are NOT rendered anywhere, yet a plain
--  select('*') shipped them for every student on every view — the main egress
--  cost. This strips them server-side; load the full row on demand if ever
--  needed to actually display a photo.
-- ===========================================================================
create or replace function public.eg_fetch_results(p_exam_id text)
returns table (
  id            uuid,
  student_id    text,
  name          text,
  score         int,
  total         int,
  percent       int,
  passed        boolean,
  violations    int,
  submitted_at  timestamptz,
  elapsed_ms    bigint,
  violation_log jsonb,
  has_webcam    boolean
)
language sql
security definer
set search_path = public
as $$
  select
    r.id, r.student_id, r.name, r.score, r.total, r.percent, r.passed,
    r.violations, r.submitted_at,
    coalesce((r.data ->> 'elapsedMs')::bigint, 0)              as elapsed_ms,
    coalesce(r.data -> 'violations', '[]'::jsonb)              as violation_log,
    (r.data ? 'webcam' and nullif(r.data ->> 'webcam','') is not null) as has_webcam
  from public.eg_results r
  where r.exam_id = p_exam_id
  order by r.submitted_at desc;
$$;
-- authenticated only (matches the eg_results read policy); students cannot call it
grant execute on function public.eg_fetch_results(text) to authenticated;

-- ===========================================================================
--  FUNCTION 2 — submit an attempt; grades server-side, enforces single attempt
-- ===========================================================================
create or replace function public.eg_submit_attempt(
  p_access_code text,
  p_name        text,
  p_student_id  text,
  p_answers     jsonb,     -- [{qid, type, value}]  (value already in ORIGINAL option indices)
  p_payload     jsonb      -- everything else: violations log, meta, webcam, timings…
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  ex       public.eg_exams;
  a        jsonb;
  q        jsonb;
  qtype    text;
  want     int[];
  got      int[];
  correct  int := 0;
  total    int := 0;
  pct      int;
  passed   boolean;
  show     boolean;
begin
  select * into ex
    from public.eg_exams
   where access_code = p_access_code and active = true
   order by updated_at desc
   limit 1;
  if not found then raise exception 'exam_not_found'; end if;

  -- single attempt
  if exists (
    select 1 from public.eg_results r
     where r.exam_id = ex.id and lower(r.student_id) = lower(p_student_id)
  ) then
    raise exception 'already_submitted';
  end if;

  -- grade each submitted answer against the hidden key
  for a in select * from jsonb_array_elements(p_answers) loop
    select qq into q
      from jsonb_array_elements(ex.config -> 'questions') qq
     where qq ->> 'id' = (a ->> 'qid')
     limit 1;
    if q is null then continue; end if;
    total := total + 1;
    qtype := q ->> 'type';

    if qtype = 'short' then
      if exists (
        select 1 from jsonb_array_elements_text(q -> 'answers') k
         where lower(btrim(k)) = lower(btrim(coalesce(a ->> 'value', '')))
      ) then correct := correct + 1; end if;
    else
      select array(select v::int from jsonb_array_elements_text(q -> 'correct') v order by 1) into want;
      select array(select v::int from jsonb_array_elements_text(a -> 'value')   v order by 1) into got;
      if want is not null and array_length(want, 1) is not null and want = got then
        correct := correct + 1;
      end if;
    end if;
  end loop;

  pct    := case when total > 0 then round(correct::numeric * 100 / total) else 0 end;
  passed := pct >= coalesce((ex.config ->> 'pass')::int, 50);

  insert into public.eg_results
    (exam_id, student_id, name, score, total, percent, passed, violations, data)
  values
    (ex.id, p_student_id, p_name, correct, total, pct, passed,
     coalesce((p_payload ->> 'violationCount')::int, 0),
     p_payload || jsonb_build_object('answers', p_answers, 'gradedAt', now()));

  show := coalesce((ex.config ->> 'showScore')::boolean, true);
  return jsonb_build_object(
    'ok',        true,
    'showScore', show,
    'score',     case when show then correct else null end,
    'total',     case when show then total   else null end,
    'percent',   case when show then pct     else null end,
    'passed',    case when show then passed  else null end
  );
end;
$$;
grant execute on function public.eg_submit_attempt(text, text, text, jsonb, jsonb) to anon, authenticated;
