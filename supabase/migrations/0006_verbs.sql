-- ============================================================================
-- 0006 · The verb layer (the only write path)
-- ----------------------------------------------------------------------------
-- Row-level security (0007) denies all direct writes. These SECURITY DEFINER
-- functions are the entire write surface. Each resolves the caller, checks the
-- feature switch and rate limit, enforces the relevant invariant, then writes
-- and stamps the policy version. All set search_path to prevent hijacking.
-- ============================================================================

-- ---- read-side helpers ----
create or replace function current_policy()
returns jsonb language sql stable as $$
  select body from policy where ratified_at is not null order by version desc limit 1
$$;

create or replace function current_policy_version()
returns integer language sql stable as $$
  select version from policy where ratified_at is not null order by version desc limit 1
$$;

-- ---- map auth.uid() to a peer, creating one on first contact ----
create or replace function ensure_peer()
returns uuid language plpgsql security definer set search_path = public, pg_temp as $$
declare v_id uuid; v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'CAIRN_NO_AUTH' using errcode = 'P0001'; end if;
  select id into v_id from peers where auth_id = v_uid;
  if v_id is null then
    insert into peers (auth_id, handle)
    values (v_uid, 'walker-' || substr(encode(gen_random_bytes(4),'hex'), 1, 6))
    returning id into v_id;
  end if;
  return v_id;
end $$;

-- ---- fold flag counts into a status, with fixed precedence ----
--      spam (hide) > nsfw (veil) > misleading/duplicate (demote) > open
create or replace function recompute_status(p_link bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare r jsonb := current_policy()->'flag_rules'; c record; v text := 'open';
begin
  select
    count(*) filter (where kind = 'spam')       as spam,
    count(*) filter (where kind = 'nsfw')       as nsfw,
    count(*) filter (where kind = 'misleading') as mis,
    count(*) filter (where kind = 'duplicate')  as dup
  into c from flags where link_id = p_link;

  if    c.spam >= (r->'spam'->>'threshold')::int       then v := 'hidden';
  elsif c.nsfw >= (r->'nsfw'->>'threshold')::int       then v := 'veiled';
  elsif c.mis  >= (r->'misleading'->>'threshold')::int
     or c.dup  >= (r->'duplicate'->>'threshold')::int  then v := 'demoted';
  end if;
  update links set status = v where id = p_link;
end $$;

-- ---- rpc_share: leave a waymark (idempotent on canonical URL) ----
--      Returns the link id. If the place already exists, returns it (invite a
--      stone instead of inserting). Sharing places no stone (sharing is free).
create or replace function rpc_share(p_url text, p_title text, p_tags text[] default '{}')
returns bigint language plpgsql security definer set search_path = public, pg_temp as $$
declare v_peer uuid; v_pol jsonb; v_hash text; v_domain text; v_link bigint; v_recent int; t text; n int := 0;
begin
  v_peer := ensure_peer();
  v_pol  := current_policy();
  if not (v_pol->'features'->>'shares')::boolean then
    raise exception 'CAIRN_FEATURE_OFF' using errcode = 'P0001'; end if;

  select count(*) into v_recent from links
   where shared_by = v_peer and created_at > now() - interval '24 hours';
  if v_recent >= (v_pol->'limits'->>'shares_per_day')::int then
    raise exception 'CAIRN_RATE_LIMIT' using errcode = 'P0001'; end if;

  v_hash   := canonicalize(p_url);
  v_domain := lower(coalesce(substring(p_url from '^[a-z]+://([^/:]+)'), 'link'));
  v_domain := regexp_replace(v_domain, '^www\.', '');

  insert into links (url, canon_hash, domain, title, shared_by)
  values (p_url, v_hash, v_domain, left(coalesce(nullif(p_title,''), p_url), 160), v_peer)
  on conflict (canon_hash) do nothing
  returning id into v_link;
  if v_link is null then
    select id into v_link from links where canon_hash = v_hash;
  end if;

  foreach t in array coalesce(p_tags, '{}') loop
    exit when n >= 5;                                   -- cap tags per share
    if t ~ '^[a-z0-9-]{1,32}$' then
      insert into link_tags (link_id, tag, added_by) values (v_link, t, v_peer)
      on conflict do nothing;
      n := n + 1;
    end if;
  end loop;

  return v_link;
end $$;

-- ---- rpc_tag: lay a trail on an existing place ----
create or replace function rpc_tag(p_link bigint, p_tag text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_peer uuid;
begin
  v_peer := ensure_peer();
  if p_tag !~ '^[a-z0-9-]{1,32}$' then raise exception 'CAIRN_BAD_TAG' using errcode = 'P0001'; end if;
  if not exists (select 1 from links where id = p_link) then
    raise exception 'CAIRN_NO_LINK' using errcode = 'P0001'; end if;
  insert into link_tags (link_id, tag, added_by) values (p_link, p_tag, v_peer)
  on conflict do nothing;
end $$;

-- ---- rpc_signal: add your stone (transfer to the sharer) ----
create or replace function rpc_signal(p_link bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_peer uuid; v_pol jsonb; v_sharer uuid; v_bal int; v_floor int; v_recent int;
begin
  v_peer := ensure_peer();
  v_pol  := current_policy();
  if not (v_pol->'features'->>'signals')::boolean then
    raise exception 'CAIRN_FEATURE_OFF' using errcode = 'P0001'; end if;

  -- I4 concurrency guard: serialize signals on (peer, link)
  perform pg_advisory_xact_lock(hashtext(v_peer::text || ':' || p_link::text)::bigint);

  if exists (                                          -- I4: one unreversed signal
    select 1 from stone_events s
    where s.kind = 'signal' and s.from_peer = v_peer and s.link_id = p_link
      and not exists (select 1 from stone_events r where r.reverses = s.id)
  ) then raise exception 'CAIRN_DUP_SIGNAL' using errcode = 'P0001'; end if;

  select shared_by into v_sharer from links where id = p_link;
  if v_sharer is null then raise exception 'CAIRN_NO_LINK' using errcode = 'P0001'; end if;
  if v_sharer = v_peer then raise exception 'CAIRN_SELF' using errcode = 'P0001'; end if; -- belt for I5

  select count(*) into v_recent from stone_events
   where kind = 'signal' and from_peer = v_peer and created_at > now() - interval '24 hours';
  if v_recent >= (v_pol->'limits'->>'signals_per_day')::int then
    raise exception 'CAIRN_RATE_LIMIT' using errcode = 'P0001'; end if;

  select coalesce(sum(qty) filter (where to_peer  = v_peer), 0)
       - coalesce(sum(qty) filter (where from_peer = v_peer), 0) into v_bal from stone_events;
  v_floor := (v_pol->'limits'->>'credit_floor')::int;
  if v_bal - 1 < v_floor then                          -- I2: floor on voluntary spend
    raise exception 'CAIRN_FLOOR' using errcode = 'P0001'; end if;

  insert into stone_events (kind, from_peer, to_peer, link_id, qty, policy_v)
  values ('signal', v_peer, v_sharer, p_link, 1, current_policy_version());
end $$;

-- ---- rpc_reclaim: reverse a specific signal (spec-faithful). No floor check:
--      reversals are bounds-exempt (I2). ----
create or replace function rpc_reclaim(p_event bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_peer uuid; v_sig stone_events;
begin
  v_peer := ensure_peer();
  select * into v_sig from stone_events where id = p_event and kind = 'signal';
  if v_sig is null then raise exception 'CAIRN_NO_SIGNAL' using errcode = 'P0001'; end if;
  if v_sig.from_peer <> v_peer then raise exception 'CAIRN_NOT_OWNER' using errcode = 'P0001'; end if;
  if exists (select 1 from stone_events r where r.reverses = p_event) then
    raise exception 'CAIRN_ALREADY_REVERSED' using errcode = 'P0001'; end if;

  insert into stone_events (kind, from_peer, to_peer, link_id, qty, reverses, policy_v)
  values ('reclaim', v_sig.to_peer, v_sig.from_peer, v_sig.link_id, 1, p_event, current_policy_version());
end $$;

-- ---- rpc_reclaim_mine: reclaim the caller's active stone on a link (the
--      client-friendly form; resolves the event id server-side). ----
create or replace function rpc_reclaim_mine(p_link bigint)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_peer uuid; v_id bigint;
begin
  v_peer := ensure_peer();
  select s.id into v_id from stone_events s
   where s.kind = 'signal' and s.from_peer = v_peer and s.link_id = p_link
     and not exists (select 1 from stone_events r where r.reverses = s.id)
   limit 1;
  if v_id is null then raise exception 'CAIRN_NO_SIGNAL' using errcode = 'P0001'; end if;
  perform rpc_reclaim(v_id);
end $$;

-- ---- rpc_flag: record graduated care, then refold the status ----
create or replace function rpc_flag(p_link bigint, p_kind text)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_peer uuid; v_pol jsonb; v_recent int;
begin
  v_peer := ensure_peer();
  v_pol  := current_policy();
  if not (v_pol->'features'->>'flags')::boolean then
    raise exception 'CAIRN_FEATURE_OFF' using errcode = 'P0001'; end if;
  if p_kind not in ('nsfw','misleading','duplicate','spam') then
    raise exception 'CAIRN_BAD_FLAG' using errcode = 'P0001'; end if;

  select count(*) into v_recent from flags
   where peer_id = v_peer and created_at > now() - interval '24 hours';
  if v_recent >= (v_pol->'limits'->>'flags_per_day')::int then
    raise exception 'CAIRN_RATE_LIMIT' using errcode = 'P0001'; end if;

  insert into flags (link_id, peer_id, kind) values (p_link, v_peer, p_kind)
  on conflict do nothing;
  perform recompute_status(p_link);
end $$;

-- ---- rpc_set_safe_mode: the one field a peer may change about their own row ----
create or replace function rpc_set_safe_mode(p_on boolean)
returns void language plpgsql security definer set search_path = public, pg_temp as $$
declare v_peer uuid;
begin
  v_peer := ensure_peer();
  update peers set safe_mode = p_on where id = v_peer;
end $$;

-- ---- break_glass: flip a feature switch by RATIFYING A NEW POLICY VERSION,
--      cloned from the active one with the flag changed and a reason attached.
--      Even the emergency is cite-as-you-enforce. service_role only (0007). ----
create or replace function break_glass(p_flag text, p_value boolean, p_reason text)
returns integer language plpgsql security definer set search_path = public, pg_temp as $$
declare v_body jsonb; v_next int;
begin
  select body into v_body from policy where ratified_at is not null order by version desc limit 1;
  v_body := jsonb_set(v_body, array['features', p_flag], to_jsonb(p_value));
  select coalesce(max(version), 0) + 1 into v_next from policy;
  insert into policy (version, body, note, ratified_at) values (v_next, v_body, p_reason, now());
  return v_next;
end $$;

-- ---- rpc_health: cheap public liveness + the I1 zero-sum self-check ----
create or replace function rpc_health()
returns jsonb language sql stable as $$
  select jsonb_build_object(
    'ok', true,
    'zero_sum', (select coalesce(sum(stones), 0) = 0 from balances)
  )
$$;
