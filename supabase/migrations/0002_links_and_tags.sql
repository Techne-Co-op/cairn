-- ============================================================================
-- 0002 · Links and trails
-- ----------------------------------------------------------------------------
-- A link is a place in the terrain. A tag is a trail laid on it. status is
-- DERIVED from flags and written only by recompute_status() in 0006; it is
-- never set by the client. The MVP folksonomy is flat (presence/absence); the
-- weighted "conviction field" is a deferred horizon, not built here.
-- ============================================================================

create table links (
  id          bigint generated always as identity primary key,
  url         text not null,
  canon_hash  text not null unique,                 -- dedupe key (see canonicalize)
  domain      text not null,
  title       text not null check (length(title) between 1 and 160),
  blurb       text check (length(blurb) <= 320),
  shared_by   uuid not null references peers(id),
  status      text not null default 'open'
              check (status in ('open','demoted','veiled','hidden')),
  created_at  timestamptz not null default now()
);

create table link_tags (
  link_id   bigint not null references links(id) on delete cascade,
  tag       text   not null check (tag ~ '^[a-z0-9-]{1,32}$'),
  added_by  uuid references peers(id),
  primary key (link_id, tag)
);

-- index for trail filtering / trending (read-path hygiene; see scoping note)
create index link_tags_tag_idx on link_tags(tag);

-- ---- canonicalize(url): produce a stable dedupe hash. Intentionally minimal
--      and conservative; an over-eager canonicalizer that collapses distinct
--      URLs is worse than one that occasionally treats near-duplicates as
--      distinct. Expand only with tests.
create or replace function canonicalize(p_url text)
returns text language plpgsql immutable as $$
declare v text;
begin
  v := lower(regexp_replace(p_url, '#.*$', ''));                       -- drop fragment
  v := regexp_replace(v, '([?&])(utm_[^=&]*|fbclid|gclid)=[^&]*', '\1', 'gi'); -- strip trackers
  v := regexp_replace(v, '[?&]+$', '');                               -- trailing separators
  return encode(digest(v, 'sha256'), 'hex');
end $$;
