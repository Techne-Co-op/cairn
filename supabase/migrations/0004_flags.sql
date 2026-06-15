-- ============================================================================
-- 0004 · Flags (graduated peer care)
-- ----------------------------------------------------------------------------
-- A flag is one peer's concern of a given kind about a place. The primary key
-- enforces one flag per peer per kind. Counts fold into a status by the rules
-- in policy (see recompute_status in 0006): enough concern covers a place, then
-- lowers it, then removes it.
-- ============================================================================

create table flags (
  link_id    bigint not null references links(id) on delete cascade,
  peer_id    uuid   not null references peers(id),
  kind       text   not null check (kind in ('nsfw','misleading','duplicate','spam')),
  created_at timestamptz not null default now(),
  primary key (link_id, peer_id, kind)
);

create index flags_link_idx on flags(link_id);
