# ExamGuard — Secure Online Exams

A single-file, browser-based exam system with lockdown and integrity monitoring.
No install and no server required — `index.html` runs on its own.

## How to run

Open `index.html` in a modern browser (Chrome/Edge recommended for fullscreen + webcam).
For best results (camera, fullscreen) serve it over `http://localhost` or `https://`, e.g.:

```bash
cd exam-guard
python3 -m http.server 4191
# then open http://localhost:4191
```

## Workflow (3 steps)

1. **Instructor builds the exam** → *Instructor → Build exam*.
   Add questions, set rules (timer, shuffling, fullscreen, max violations, single attempt…),
   then **Export exam package (.json)**. Send that file **plus `index.html`** to students.
   ⚠️ The package contains a private signing salt — only give it to students who are sitting the exam.

2. **Students take it** → *Student*. They load the package, enter name/ID + access code,
   accept the honor code (and webcam photo if required), then sit the exam locked down.
   On submit they **download a result file** and return it to you (email / upload).

3. **Instructor grades** → *Instructor → Grade results*.
   Load the same exam package, import the returned result files. Objective questions are
   auto-graded; you get scores, integrity flags, and a CSV export.

## Anti-cheat features

| Feature | What it does |
|---|---|
| Fullscreen enforcement | Forces fullscreen; flags any exit |
| Tab-switch / focus detection | Logs when the student leaves the tab or window |
| Copy / paste / right-click block | Disables clipboard, context menu, text selection, drag |
| Shortcut blocking | Blocks dev-tools (F12, Ctrl+Shift+I/J/C), view-source, print, save |
| Randomization | Per-student shuffle of questions **and** options (deterministic, verifiable) |
| Question pool | Serve N random questions out of a larger pool |
| Timers | Global exam timer + optional per-question limit |
| Single attempt | One submission per student ID on a device |
| Idle / resize / multi-monitor | Logs inactivity, window resizes, and extended displays |
| Webcam check-in | Optional ID snapshot stored with the result |
| Tamper-evident results | SHA-256 signature using the exam salt — edited scores are flagged `TAMPERED` |
| Auto-submit | After the configured number of violations |

## Honest limitations

A browser app **cannot** do OS-level lockdown, detect a second phone, or run AI webcam
proctoring like commercial tools (Respondus, Honorlock, Proctorio). ExamGuard is a strong
**deterrent + evidence-collection** layer. Pair it with good assessment design (question
pools, tight timing, higher-order open questions) and always have a human review integrity
flags before any decision.

---

## Cloud mode (Supabase) — automatic results, no shared answer keys

By default ExamGuard runs in **local file mode** (export package → students return result files).
Turning on cloud mode removes the file shuffle and closes a real weakness of file mode: in file
mode the package contains the correct answers and the signing salt, so a determined student could
read them. In cloud mode the answer key never leaves the server.

**What changes in cloud mode**
- Students **join by access code** — no package file, no answer key, no salt in the browser.
- Submissions are **graded in the database** against the hidden answer key and stored automatically.
  A student cannot forge a score or edit a result file, and single-attempt is enforced in SQL.
- Instructors **sign in**, publish exams, and **pull live results** (already graded) with CSV export.

**Setup (one time, ~3 minutes)**
1. Create a Supabase project (or reuse your `sentinel-ra` one — the tables here are prefixed
   `eg_` so they won't collide).
2. Open the Supabase **SQL Editor**, paste all of [`supabase/schema.sql`](supabase/schema.sql), and **Run**.
3. In **Authentication → Providers**, keep Email on. Create an instructor account from the app
   ("Create account"), or add it under Authentication → Users. (Disable "Confirm email" for the
   fastest start, or confirm via the email link.)
4. Put your project URL + **anon/public** key into [`js/config.js`](js/config.js). Never use the
   `service_role` key in the browser.
5. Reload. The instructor console now shows a sign-in bar and a **☁ Publish to cloud** button;
   the student screen shows **Join by access code**.

**Cloud workflow**
1. Instructor: sign in → build exam → **☁ Publish to cloud**. Give students only the access code.
2. Students: *Student* → enter access code → take exam → submit (auto-graded, auto-stored).
3. Instructor: *Grade results* → pick the exam → **☁ Pull live results** → review / export CSV.

> File mode still works whenever `js/config.js` is blank, so you can demo offline and switch to
> cloud for real cohorts without code changes.

---

## Student guide / landing page

`guide.html` is a friendly, student-facing page (checklist, rules, step-by-step, troubleshooting).
Send students there instead of the raw app. Its **Join exam** button carries the typed access code
straight into the app via a deep link: `index.html?code=ACCESS-CODE#student`.

Deep links the app understands:
- `index.html#student` — open the student join screen
- `index.html?code=XXXX#student` — open it with the access code prefilled
- `index.html#admin` — open the instructor console

## Email notifications (optional — not active by default)

`supabase/email-notifications.sql` adds instructor email alerts on submission using Supabase
`pg_net` + [Resend](https://resend.com) — no server to deploy. Add your Resend API key and recipient
in the file, run it in the SQL Editor, and you're done. A commented variant emails **only flagged**
submissions. Remove the trigger to turn it off.

## Custom domain (GitHub Pages)

1. Add a `CNAME` file at the repo root containing just your domain (e.g. `exams.yourschool.edu`).
2. At your DNS provider, point the domain at GitHub Pages:
   - Subdomain (e.g. `exams.…`): a **CNAME** record → `niikpakpoe.github.io`
   - Apex/root (e.g. `yourschool.edu`): four **A** records → `185.199.108.153`, `185.199.109.153`,
     `185.199.110.153`, `185.199.111.153`
3. In the repo: **Settings → Pages → Custom domain**, enter the domain, and enable **Enforce HTTPS**.
