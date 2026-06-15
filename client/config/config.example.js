/*
  Cairn client config  ·  TEMPLATE
  --------------------------------------------------------------------------
  Copy this file to  config.js  (same folder) and fill in your project's
  values. The presence of config.js flips the client from the seeded DEMO to
  the LIVE Supabase backend; absent it, the demo runs.

  Both values below are PUBLISHABLE. The anon key is a public client key:
  security is enforced by row-level security and the verb layer in the
  database (see supabase/migrations/0007_rls.sql), not by hiding this key.
  The service_role key must NEVER appear here or anywhere in the client.

      cp config.example.js config.js     # then edit config.js
*/
window.CAIRN_CONFIG = {
  url:     "https://YOUR-PROJECT-REF.supabase.co",
  anonKey: "YOUR-PUBLIC-ANON-KEY"
};
