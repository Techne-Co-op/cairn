-- ============================================================================
-- seed.sql · LOCAL DEVELOPMENT ONLY
-- ----------------------------------------------------------------------------
-- Populates a local stack (supabase db reset) with a small, believable map so
-- the interface has something to render before the first real peer signs in.
-- Seeded peers have a NULL auth_id (they are not real auth users); the real
-- "you" peer is created by ensure_peer() at sign-in. Do NOT run this on the
-- remote project.
-- ============================================================================

insert into peers (handle, is_commons) values
  ('rill', false), ('fen', false), ('morrow', false), ('slate', false);

insert into links (url, canon_hash, domain, title, shared_by) values
  ('https://archive.example/memex-1945', canonicalize('https://archive.example/memex-1945'),
     'archive.example', 'As We May Think, in full', (select id from peers where handle='morrow')),
  ('https://docs.example/ostrom-commons-rules', canonicalize('https://docs.example/ostrom-commons-rules'),
     'docs.example', 'Eight rules real commons use to govern themselves', (select id from peers where handle='rill')),
  ('https://news.example/city-budget-open-data', canonicalize('https://news.example/city-budget-open-data'),
     'news.example', 'City publishes its budget as queryable open data', (select id from peers where handle='fen')),
  ('https://blog.example/forever-stamp-economics', canonicalize('https://blog.example/forever-stamp-economics'),
     'blog.example', 'Why a stamp holds value when a coin does not', (select id from peers where handle='morrow')),
  ('https://example.net/unverified-merger-rumor', canonicalize('https://example.net/unverified-merger-rumor'),
     'example.net', 'Sources claim a merger that filings do not show', (select id from peers where handle='slate')),
  ('https://example.com/sensitive-explicit-thread', canonicalize('https://example.com/sensitive-explicit-thread'),
     'example.com', 'A thread some flagged as not-safe-for-trails', (select id from peers where handle='fen'));

insert into link_tags (link_id, tag, added_by)
select l.id, t.tag, (select id from peers where handle='rill')
from (values
  ('https://archive.example/memex-1945','primary-source'),
  ('https://archive.example/memex-1945','history'),
  ('https://docs.example/ostrom-commons-rules','commons'),
  ('https://news.example/city-budget-open-data','open-data'),
  ('https://news.example/city-budget-open-data','civic'),
  ('https://blog.example/forever-stamp-economics','economics'),
  ('https://example.net/unverified-merger-rumor','rumor')
) as t(url, tag)
join links l on l.url = t.url;

-- a believable signal history (all transfers; the ledger stays zero-sum)
insert into stone_events (kind, from_peer, to_peer, link_id, qty, policy_v, created_at)
select 'signal',
       (select id from peers where handle = s.frm),
       l.shared_by, l.id, 1, 1, now() - (s.hours || ' hours')::interval
from (values
  ('rill','https://archive.example/memex-1945', 50),
  ('fen', 'https://archive.example/memex-1945', 33),
  ('slate','https://archive.example/memex-1945', 22),
  ('rill','https://docs.example/ostrom-commons-rules', 20),
  ('fen', 'https://docs.example/ostrom-commons-rules', 12),
  ('morrow','https://docs.example/ostrom-commons-rules', 8),
  ('rill','https://news.example/city-budget-open-data', 20),
  ('slate','https://news.example/city-budget-open-data', 14),
  ('morrow','https://news.example/city-budget-open-data', 6),
  ('rill','https://blog.example/forever-stamp-economics', 40),
  ('fen','https://blog.example/forever-stamp-economics', 9)
) as s(frm, url, hours)
join links l on l.url = s.url
where l.shared_by <> (select id from peers where handle = s.frm);

-- flags: veil the sensitive thread (2 nsfw), demote the rumor (3 misleading)
insert into flags (link_id, peer_id, kind)
select l.id, (select id from peers where handle = f.peer), f.kind
from (values
  ('https://example.com/sensitive-explicit-thread','rill','nsfw'),
  ('https://example.com/sensitive-explicit-thread','morrow','nsfw'),
  ('https://example.net/unverified-merger-rumor','rill','misleading'),
  ('https://example.net/unverified-merger-rumor','fen','misleading'),
  ('https://example.net/unverified-merger-rumor','morrow','misleading')
) as f(url, peer, kind)
join links l on l.url = f.url;

-- fold the seeded flags into statuses
select recompute_status(id) from links;
