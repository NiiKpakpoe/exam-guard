/* =========================================================================
   ExamGuard — cloud configuration
   -------------------------------------------------------------------------
   Leave BOTH values blank to run in LOCAL FILE mode (export package files /
   import result files — the original standalone behaviour).

   Fill them in to enable CLOUD mode:
     • Students join an exam by access code (no package file, no answer key
       ever reaches the browser).
     • Submissions are graded server-side and stored automatically.
     • Instructors sign in to publish exams and pull live results.

   • supabaseUrl     — your project URL, e.g. https://abcdxyz.supabase.co
   • supabaseAnonKey — the "anon / public" key. SAFE to expose in the browser;
                       row-level security + SECURITY DEFINER functions protect
                       answer keys and results. NEVER put the service_role key here.

   Run supabase/schema.sql in the Supabase SQL editor once before using cloud mode.
   -------------------------------------------------------------------------
   SHELVED 2026-06-30: decoupled from the shared Supabase project
   (fpwbvtoqabaiisqugqwi, used by sentinel-ra). Both values are blank, so the
   app runs in LOCAL FILE mode and connects to NO backend. To bring ExamGuard
   back online, follow supabase/MIGRATION-RUNBOOK.md and SHELVED.md, then fill
   in the NEW project's URL + anon key below. Do NOT reuse the old shared
   project — give ExamGuard its own.
   ========================================================================= */
window.EG_CONFIG = {
  supabaseUrl: '',
  supabaseAnonKey: ''
};
