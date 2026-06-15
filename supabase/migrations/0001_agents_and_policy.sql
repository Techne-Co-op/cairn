-- ============================================================================
-- 0001 · Agents and the policy book
-- ----------------------------------------------------------------------------
-- Establishes identity (peers), the single commons account, and the policy
-- table whose newest ratified row carries every threshold, limit, and feature
-- switch. Every economic event later stamps the policy version in force (I6),
-- so the rules a record was made under are always recoverable.
-- ============================================================================

create extension if not exists pgcrypto;   -- gen_random_uuid, digest, gen_random_bytes

-- ---- peers: the agents. A pseudonymous account, optionally bound to a
--      Supabase auth user. safe_mode is the reader's own safe-trails setting.
create table peers (
  id          uuid primary key default gen_random_uuid(),
  auth_id     uuid unique references auth.users(id) on delete set null,
  handle      text unique check (handle ~ '^[a-z0-9-]{3,24}$'),
  safe_mode   boolean not null default true,
  is_commons  boolean not null default false,
  created_at  timestamptz not null default now()
);
-- exactly one commons account may exist
create unique index one_commons on peers(is_commons) where is_commons;

-- ---- policy: a versioned, append-only agreement. The newest ratified row is
--      authoritative. Never edit a row to change the rules; ratify a new one.
create table policy (
  version     integer primary key,
  body        jsonb   not null,
  note        text,
  ratified_at timestamptz
);

-- the one commons account, through which all escrow-style flows pass
insert into peers (handle, is_commons) values ('commons', true);

-- ---- interim policy v1 (B2: the stewards hold the pen during the alpha).
--      Every value here is PROPOSED and unratified by the membership.
insert into policy (version, body, note, ratified_at) values (
  1,
  '{
    "features":   { "signals": true, "shares": true, "flags": true, "signups": false },
    "limits":     { "credit_floor": -10, "credit_ceiling": 200,
                    "signals_per_day": 30, "flags_per_day": 10, "shares_per_day": 10 },
    "flag_rules": { "nsfw":       { "threshold": 2, "effect": "veil"   },
                    "misleading": { "threshold": 3, "effect": "demote" },
                    "duplicate":  { "threshold": 3, "effect": "demote" },
                    "spam":       { "threshold": 4, "effect": "hide"   } }
  }'::jsonb,
  'interim policy v1 (proposed) - alpha launch parameters',
  now()
);

-- NOTE: signups starts FALSE. Opening the public door is a deliberate act done
-- through break_glass() after counsel and the operator-removal policy are in
-- place. See the README "going public" section.
