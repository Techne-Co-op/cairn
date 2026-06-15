# Cairn

Way-finding for the open web. A commons where peers leave waymarks and the map
of what is worth attention draws itself from the many who walked before.

This repository is the MVP: a static client served from GitHub Pages over a
Supabase Postgres backend. It is an *alpha*, not a public launch; see
[Going public](#going-public) for what gates that.

```
status   alpha · concept with a working build · not yet public
scope    flat folksonomy + the zero-sum stone ledger + graduated care + safe trails
defer    the conviction field, the service-credit denomination, realtime, demurrage
```

---

## Architecture

Two pieces, no server in between.

```
  GitHub Pages (static client)                 Supabase (Postgres + Auth)
  ----------------------------                 --------------------------
  client/index.html                            verbs  (SECURITY DEFINER)  ← the only write path
    · vanilla JS, no framework      writes  →  rpc_share / rpc_signal / rpc_flag / ...
    · ports-and-adapters store      reads   ←  feed view (redaction) + folds
    · supabase-js (lazy import)                row-level security: deny by default
```

The client never talks to tables directly. It depends on a `CairnStore`
interface with two adapters: a seeded in-memory `LocalStore` (so the page runs
with no backend, as a demo and as a faithful reference of the rules), and a
`SupabaseStore` (the production path). The presence of `client/config/config.js`
selects the live path and flips the on-screen chip from `demo` to `live`.

Correctness and safety live in the database, not the client:

- **Balances and stone counts are folds** over an append-only event log, never
  stored columns.
- **The ledger is append-only**; a reclaim is a new reversing event.
- **Safe-trails redaction is server-side**, in the `feed` view, before any bytes
  leave. The client veil is cosmetic.
- **Row-level security denies all direct table access**; the `rpc_*` verbs are
  the entire write surface, and they enforce feature switches, per-peer rate
  limits, and the stone invariants.

---

## Repository layout

```
cairn/
├── README.md
├── LICENSE                         AGPL-3.0-or-later (proposed)
├── DATA_LICENSE                    ODbL (proposed)
├── SECURITY.md
├── supabase/
│   ├── config.toml                 CLI config; anonymous sign-ins enabled
│   ├── seed.sql                    local-only sample map
│   └── migrations/
│       ├── 0001_agents_and_policy.sql
│       ├── 0002_links_and_tags.sql
│       ├── 0003_ledger.sql
│       ├── 0004_flags.sql
│       ├── 0005_views.sql          folds + the feed redaction view
│       ├── 0006_verbs.sql          the rpc_* write surface
│       └── 0007_rls.sql            deny-by-default + grants
├── client/
│   ├── index.html                  the way-finding HUD
│   └── config/
│       └── config.example.js       copy to config.js
└── .github/workflows/
    ├── deploy-pages.yml            publish client/ to GitHub Pages
    └── ci.yml                      replay the migration chain on every PR
```

---

## Setup

### 1 · Apply the schema

You have a Supabase project. Apply the seven migrations in order. Two ways:

**A. SQL editor (simplest).** Open the project's SQL editor and run the contents
of `supabase/migrations/0001_…` through `0007_…` in order, one after another.

**B. Supabase CLI (repeatable).**
```bash
npm install -g supabase           # if needed
supabase link --project-ref YOUR-PROJECT-REF
supabase db push                  # applies migrations/ in order
```
For a local stack with sample data:
```bash
supabase start                    # local Postgres + Studio
supabase db reset                 # replays migrations + seed.sql
```

### 2 · Enable anonymous sign-ins

Every visitor becomes a peer without an email, so the backend can rate-limit and
attribute without collecting personal data. In the dashboard:
**Authentication → Sign In / Providers → Anonymous sign-ins → enable.**
(The local stack already has this, via `config.toml`.) This toggle is easy to
miss and the client cannot work without it.

### 3 · Point the client at the project

```bash
cd client/config
cp config.example.js config.js     # then edit config.js
```
Fill in your project URL and the **public anon key** (Project Settings → API).
Both are publishable; security is the RLS and verb layer, not key secrecy. The
`service_role` key must never appear in the client.

### 4 · Run it

- **Local:** open `client/index.html` over a static server
  (`npx serve client`), not `file://`, so the module and config load.
- **GitHub Pages:** enable Pages for the repo with source = GitHub Actions; the
  included `deploy-pages.yml` publishes the `client/` directory on push to main.

---

## Apply-and-verify (the first walk)

Once live, walk it once by hand to confirm the machine before anyone else
arrives:

- [ ] the map renders from the database (not the demo chip)
- [ ] leave a waymark → it appears
- [ ] add a stone to someone else's waymark → its height rises, your balance falls
- [ ] reclaim it → height and balance return
- [ ] lay a trail (tag) → it shows on the card and in the trails rail
- [ ] flag a place to its threshold → it veils or demotes; safe-trails redacts it
- [ ] in the SQL editor, freeze the economy and confirm a verb refuses politely:
      ```sql
      select break_glass('signals', false, 'first-walk: testing the kill switch');
      -- a subsequent rpc_signal now raises CAIRN_FEATURE_OFF
      select break_glass('signals', true, 'first-walk: restoring');
      ```
- [ ] `select rpc_health();` returns `{"ok": true, "zero_sum": true}`

---

## Free-tier notes

A free Supabase project is right for the alpha, with two specifics:

- **It pauses after inactivity.** A scheduled health ping keeps it awake. The
  ping workflow is part of the deployment plan and is added when the project
  carries anything real.
- **It has no managed backups.** A nightly encrypted `pg_dump` to a private repo
  is the backup layer. Also from the deployment plan; not needed for the first
  private walk, required before real contributions accumulate.

Neither blocks setup. Both matter the moment something real lives in the project.

---

## Security posture

- RLS is deny-by-default on every table; reads go through views, writes through
  the `rpc_*` verbs only.
- The anon key is public by design; the `service_role` key is never shipped.
- `break_glass` (the kill switches) is `service_role` only and flips a switch by
  ratifying a new policy version with a reason, so even an emergency is auditable.
- **Unaudited.** Before going public, the schema and verbs want a review, and the
  legal and operational items below must be in place.

---

## Going public

The alpha is private. Opening the public door (flipping the `signups` switch) is
a deliberate, later act that depends on items outside this repo:

- counsel review of the closed-loop, non-redeemable stones language (terms) — **D1**
- the erasure / scrub-to-tombstone procedure under an append-only ledger — **D2**
- an operator hard-removal path for illegal content, beyond the flag thresholds
- the start-tier and budget decision

These gate *public*, which is a trust step, not a scale step. Scaling levers
(a `link_stats` materialization, a CDN on the feed, point-in-time recovery) wait
for a measured number and are not needed for the alpha.

---

## What is deliberately not here

Scale-by-trigger, not by anticipation. The MVP omits, on purpose: a separate
application server (PostgREST + the verbs are the API), any queue or worker fleet,
realtime (polling suffices), a search service, and the entire service-credit /
on-chain economy, which is a far-horizon concept rather than the alpha. The
weighted "conviction field" is likewise deferred; the MVP folksonomy is flat.

---

## License

Code: AGPL-3.0-or-later (proposed, pending ratification). Data: ODbL (proposed).
See `LICENSE` and `DATA_LICENSE`.
