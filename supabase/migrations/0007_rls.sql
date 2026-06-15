-- ============================================================================
-- 0007 · Authorization (RLS deny-by-default, then grants)
-- ----------------------------------------------------------------------------
-- This is what makes a public anon key safe to ship. RLS denies all direct
-- table access; reads flow through views, writes through verbs. The only
-- policies are narrow read policies for a peer's own row and its own ledger
-- lines. No INSERT/UPDATE/DELETE policy exists for anon/authenticated, so all
-- direct DML is denied and the SECURITY DEFINER verbs are the sole write path.
-- ============================================================================

alter table peers        enable row level security;
alter table links        enable row level security;
alter table link_tags    enable row level security;
alter table stone_events enable row level security;
alter table flags        enable row level security;

-- a peer may read only its own row
create policy peer_self_read on peers
  for select using (auth_id = auth.uid());

-- a peer may read ledger lines it is a party to (for any future "your stones" view)
create policy ledger_party_read on stone_events
  for select using (
    from_peer in (select id from peers where auth_id = auth.uid()) or
    to_peer   in (select id from peers where auth_id = auth.uid())
  );

-- deny all direct table access to the public roles; views and verbs are the API
revoke all on peers, links, link_tags, stone_events, flags from anon, authenticated;

-- expose the read views
grant select on feed, link_stones, trending_tags, hidden_count, my_balance
  to anon, authenticated;

-- expose the verbs (the only write path)
grant execute on function
  rpc_share(text, text, text[]),
  rpc_tag(bigint, text),
  rpc_signal(bigint),
  rpc_reclaim(bigint),
  rpc_reclaim_mine(bigint),
  rpc_flag(bigint, text),
  rpc_set_safe_mode(boolean),
  rpc_health(),
  ensure_peer()
  to anon, authenticated;

-- break_glass is an operator action: service_role only (never the client)
grant execute on function break_glass(text, boolean, text) to service_role;
