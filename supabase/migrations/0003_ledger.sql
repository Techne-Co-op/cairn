-- ============================================================================
-- 0003 · The stone ledger (append-only mutual credit)
-- ----------------------------------------------------------------------------
-- Every stone is a TRANSFER. A signal moves one stone from a peer to the sharer
-- of the link they value; a reclaim is a NEW reversing row, never an edit. With
-- both parties NOT NULL and no mint path, the global balance is structurally
-- zero (I1). The constraints below make self-dealing (I5) and double-spend of a
-- reversal unrepresentable.
-- ============================================================================

create table stone_events (
  id          bigint generated always as identity primary key,
  kind        text not null check (kind in ('signal','reclaim','demurrage','grant')),
  from_peer   uuid not null references peers(id),
  to_peer     uuid not null references peers(id),
  link_id     bigint references links(id),
  qty         integer not null check (qty > 0),
  reverses    bigint references stone_events(id),
  policy_v    integer not null references policy(version),
  created_at  timestamptz not null default now(),
  check (from_peer <> to_peer),                  -- I5: self-deal is unrepresentable
  check (kind <> 'signal'  or qty = 1),          -- a signal is exactly one stone
  check (kind <> 'reclaim' or reverses is not null)
);

-- I4 support: a given signal can be reversed at most once
create unique index one_reversal on stone_events(reverses) where reverses is not null;

-- read-path hygiene: the folds (balances, link_stones) scan by these columns
create index stone_events_link_idx    on stone_events(link_id);
create index stone_events_from_idx    on stone_events(from_peer);
create index stone_events_to_idx      on stone_events(to_peer);
create index stone_events_reverses_idx on stone_events(reverses);

-- I3: the ledger is append-only. The verbs (SECURITY DEFINER) insert; nobody
-- updates or deletes. RLS in 0007 also denies; this revoke is belt-and-braces.
revoke update, delete on stone_events from anon, authenticated;
