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
   ========================================================================= */
window.EG_CONFIG = {
  supabaseUrl: 'https://fpwbvtoqabaiisqugqwi.supabase.co',
  supabaseAnonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZwd2J2dG9xYWJhaWlzcXVncXdpIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE1MjYwMjMsImV4cCI6MjA5NzEwMjAyM30.RZtSmuOGNcaNVXojPuinE35sVdugDKYKoveKtziL5kg'
};
