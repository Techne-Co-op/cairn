# Security

Cairn is an unaudited alpha. Please report vulnerabilities privately rather than
opening a public issue.

## Reporting

Email the maintainers at the address listed on the project's public page, or open
a GitHub private security advisory on this repository. Include steps to reproduce
and the affected surface (client, a verb, an RLS policy, the redaction view).

## What we care about most

- Any path that lets an anonymous client write tables directly (bypassing the
  `rpc_*` verbs) or read past the `feed` view's safe-trails redaction.
- Any way to violate a stone invariant: minting stones, taking a balance below
  the floor on a voluntary spend, editing or deleting ledger rows, or signaling
  one's own waymark.
- Any leak of the `service_role` key or of a veiled link's content to a safe
  reader.

## Scope

The anon key is public by design; reporting that it is visible in the client is
not a vulnerability. Security rests on row-level security and the verb layer
(see `supabase/migrations/0007_rls.sql`), which is the right place to probe.
