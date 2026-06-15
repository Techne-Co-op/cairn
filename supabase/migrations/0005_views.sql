-- ============================================================================
-- 0005 · Derivations (folds) and the redaction boundary
-- ----------------------------------------------------------------------------
-- Balances, stone counts, trends, and statuses are NEVER stored as primary
-- columns. They are computed from the event log and the flags on read. The
-- `feed` view is where safe-trails redaction happens, at the database edge,
-- before any bytes reach a client. The client veil is cosmetic; THIS is the
-- enforcement.
--
-- These views are owned by the migration role and so read the base tables past
-- the RLS added in 0007 (do NOT set security_invoker on them, or they would be
-- blocked). Direct table reads by anon stay denied; reads flow through views.
-- ============================================================================

-- reader's effective safe-mode. Anonymous and unknown readers default to SAFE.
create or replace function reader_safe()
returns boolean language sql stable as $$
  select coalesce((select safe_mode from peers where auth_id = auth.uid()), true)
$$;

-- every peer's balance = stones received minus stones sent (I1: sums to zero)
create view balances as
  select p.id as peer_id,
         coalesce(sum(e.qty) filter (where e.to_peer  = p.id), 0)
       - coalesce(sum(e.qty) filter (where e.from_peer = p.id), 0) as stones
  from peers p
  left join stone_events e on p.id in (e.from_peer, e.to_peer)
  group by p.id;

-- the caller's own balance (one row), for the client's "stones" readout
create view my_balance as
  select coalesce(sum(e.qty) filter (where e.to_peer  = p.id), 0)
       - coalesce(sum(e.qty) filter (where e.from_peer = p.id), 0) as stones
  from peers p
  left join stone_events e on p.id in (e.from_peer, e.to_peer)
  where p.auth_id = auth.uid()
  group by p.id;

-- a signal is "active" while it has no reversing reclaim
create view active_signals as
  select s.id, s.from_peer as peer_id, s.link_id, s.created_at
  from stone_events s
  where s.kind = 'signal'
    and not exists (select 1 from stone_events r where r.reverses = s.id);

-- stones (height) and breadth (distinct hands) per link
create view link_stones as
  select link_id,
         count(*)::int                  as stones,
         count(distinct peer_id)::int   as breadth
  from active_signals
  group by link_id;

-- trending trails: stones weighted by an event-age half-life (~12h "today").
-- Single-window for the MVP; per-window trending is deferred.
create view trending_tags as
  select lt.tag,
         coalesce(sum(
           power(0.5, extract(epoch from now() - a.created_at) / 3600 / 12)
         ), 0) as score
  from link_tags lt
  join links l on l.id = lt.link_id and l.status in ('open','demoted')
  left join active_signals a on a.link_id = l.id
  group by lt.tag
  order by score desc;

-- how many places are hidden (so a surface can say so without revealing them)
create view hidden_count as
  select count(*)::int as n from links where status = 'hidden';

-- ---- THE REDACTION VIEW. The only read path the client uses for links.
--      A veiled link is nulled for safe readers; hidden links are excluded for
--      everyone. security_barrier keeps the redaction predicate from leaking.
create view feed with (security_barrier = true) as
  select l.id,
         case when l.status = 'veiled' and reader_safe() then null else l.title  end as title,
         case when l.status = 'veiled' and reader_safe() then null else l.blurb  end as blurb,
         case when l.status = 'veiled' and reader_safe() then null else l.url    end as url,
         case when l.status = 'veiled' and reader_safe() then null else l.domain end as domain,
         l.status, l.created_at, l.shared_by,
         coalesce(ls.stones, 0)  as stones,
         coalesce(ls.breadth, 0) as breadth,
         (select array_agg(tag order by tag) from link_tags where link_id = l.id) as tags
  from links l
  left join link_stones ls on ls.link_id = l.id
  where l.status <> 'hidden';
