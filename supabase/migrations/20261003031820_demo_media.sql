-- Demo media is a public read bucket. Writes stay on the service role behind Admin routes.
-- Paths are demo/{entityType}/{entityId}/{file}. Production buckets are untouched.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'demo-media',
  'demo-media',
  true,
  104857600,
  array['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'video/mp4', 'video/quicktime', 'video/webm']
)
on conflict (id) do update
set public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists demo_media_public_read on storage.objects;
create policy demo_media_public_read
  on storage.objects
  for select
  to anon, authenticated
  using (bucket_id = 'demo-media' and name like 'demo/%');

alter table demo.publications
  add column if not exists change_summary jsonb;

create or replace function demo.json_id_diff(p_before jsonb, p_after jsonb)
returns jsonb
language plpgsql
immutable
as $fn$
declare
  v_before jsonb := case when jsonb_typeof(p_before) = 'array' then p_before else '[]'::jsonb end;
  v_after jsonb := case when jsonb_typeof(p_after) = 'array' then p_after else '[]'::jsonb end;
  v_map jsonb := '{}'::jsonb;
  v_seen jsonb := '{}'::jsonb;
  v_item jsonb;
  v_id text;
  v_added integer := 0;
  v_changed integer := 0;
  v_removed integer := 0;
begin
  for v_item in select value from jsonb_array_elements(v_before)
  loop
    v_id := coalesce(nullif(v_item->>'id', ''), nullif(v_item->>'roomID', '') || ':' || nullif(v_item->>'profileID', ''), '');
    if v_id <> '' then
      v_map := v_map || jsonb_build_object(v_id, v_item);
    end if;
  end loop;

  for v_item in select value from jsonb_array_elements(v_after)
  loop
    v_id := coalesce(nullif(v_item->>'id', ''), nullif(v_item->>'roomID', '') || ':' || nullif(v_item->>'profileID', ''), '');
    if v_id = '' then
      continue;
    end if;
    v_seen := v_seen || jsonb_build_object(v_id, true);
    if v_map ? v_id then
      if (v_map->v_id) is distinct from v_item then
        v_changed := v_changed + 1;
      end if;
    else
      v_added := v_added + 1;
    end if;
  end loop;

  select count(*) into v_removed
  from jsonb_object_keys(v_map) as object_key
  where not (v_seen ? object_key);

  return jsonb_build_object('added', v_added, 'changed', v_changed, 'removed', v_removed);
end;
$fn$;

create or replace function demo.change_summary(p_before jsonb, p_after jsonb)
returns jsonb
language plpgsql
stable
as $fn$
declare
  v_counts jsonb := '{}'::jsonb;
  v_lines jsonb := '[]'::jsonb;
  v_key text;
  v_label text;
  v_diff jsonb;
  v_before_profiles jsonb;
  v_after_profiles jsonb;
  v_pair record;
begin
  if p_before is null then
    p_before := '{}'::jsonb;
  end if;
  if p_after is null then
    p_after := '{}'::jsonb;
  end if;

  v_before_profiles := coalesce(p_before->'peers', '[]'::jsonb);
  if jsonb_typeof(p_before->'viewer') = 'object' then
    v_before_profiles := v_before_profiles || jsonb_build_array(p_before->'viewer');
  end if;
  if jsonb_typeof(p_before->'host') = 'object' then
    v_before_profiles := v_before_profiles || jsonb_build_array(p_before->'host');
  end if;

  v_after_profiles := coalesce(p_after->'peers', '[]'::jsonb);
  if jsonb_typeof(p_after->'viewer') = 'object' then
    v_after_profiles := v_after_profiles || jsonb_build_array(p_after->'viewer');
  end if;
  if jsonb_typeof(p_after->'host') = 'object' then
    v_after_profiles := v_after_profiles || jsonb_build_array(p_after->'host');
  end if;

  v_counts := v_counts || jsonb_build_object('profiles', demo.json_id_diff(v_before_profiles, v_after_profiles));

  for v_pair in
    select * from (values
      ('accounts', 'Accounts'),
      ('trades', 'Trades'),
      ('posts', 'Posts'),
      ('clips', 'Clips'),
      ('stories', 'Stories'),
      ('achievements', 'Achievements'),
      ('activity', 'Activity'),
      ('conversations', 'Conversations'),
      ('messages', 'Messages'),
      ('channels', 'Channels'),
      ('memberships', 'Room members'),
      ('roomMessages', 'Room messages'),
      ('checkIns', 'Check-ins'),
      ('payouts', 'Payouts'),
      ('vaultFolders', 'Vault folders'),
      ('vaultItems', 'Vault items')
    ) as pairs(key, label)
  loop
    v_counts := v_counts || jsonb_build_object(v_pair.key, demo.json_id_diff(p_before->v_pair.key, p_after->v_pair.key));
  end loop;

  if jsonb_typeof(p_before->'room') = 'object' or jsonb_typeof(p_after->'room') = 'object' then
    if p_before->'room' is not distinct from p_after->'room' then
      v_diff := jsonb_build_object('added', 0, 'changed', 0, 'removed', 0);
    elsif p_before->'room' is null then
      v_diff := jsonb_build_object('added', 1, 'changed', 0, 'removed', 0);
    elsif p_after->'room' is null then
      v_diff := jsonb_build_object('added', 0, 'changed', 0, 'removed', 1);
    else
      v_diff := jsonb_build_object('added', 0, 'changed', 1, 'removed', 0);
    end if;
    v_counts := v_counts || jsonb_build_object('room', v_diff);
  end if;

  for v_key, v_label in
    select * from (values
      ('profiles', 'Profiles'),
      ('accounts', 'Accounts'),
      ('trades', 'Trades'),
      ('posts', 'Posts'),
      ('clips', 'Clips'),
      ('stories', 'Stories'),
      ('achievements', 'Achievements'),
      ('activity', 'Activity'),
      ('conversations', 'Conversations'),
      ('messages', 'Messages'),
      ('room', 'Trade Room'),
      ('memberships', 'Room members'),
      ('roomMessages', 'Room messages'),
      ('checkIns', 'Check-ins'),
      ('payouts', 'Payouts'),
      ('vaultFolders', 'Vault folders'),
      ('vaultItems', 'Vault items')
    ) as labels(key, label)
  loop
    v_diff := v_counts->v_key;
    if v_diff is null then
      continue;
    end if;
    if coalesce((v_diff->>'added')::int, 0) > 0
      or coalesce((v_diff->>'changed')::int, 0) > 0
      or coalesce((v_diff->>'removed')::int, 0) > 0 then
      v_lines := v_lines || jsonb_build_array(format(
        '%s +%s / ~%s / -%s',
        v_label,
        v_diff->>'added',
        v_diff->>'changed',
        v_diff->>'removed'
      ));
    end if;
  end loop;

  return jsonb_build_object('counts', v_counts, 'lines', v_lines);
end;
$fn$;

create or replace function demo.referenced_media_paths()
returns text[]
language sql
stable
security definer
set search_path = demo, pg_temp
as $fn$
  with recursive docs as (
    select payload as doc from profiles
    union all select payload from accounts
    union all select payload from trades
    union all select payload from posts
    union all select payload from clips
    union all select payload from stories
    union all select payload from achievements
    union all select payload from activity
    union all select payload from conversations
    union all select payload from messages
    union all select payload from rooms
    union all select payload from room_channels
    union all select payload from room_memberships
    union all select payload from room_messages
    union all select payload from check_ins
    union all select payload from payouts
    union all select payload from vault_folders
    union all select payload from vault_items
    union all select snapshot from publications
  ),
  walk as (
    select doc as node from docs
    union all
    select entry.value
    from walk
    cross join lateral jsonb_array_elements(
      case
        when jsonb_typeof(node) = 'object' then coalesce((select jsonb_agg(child.value) from jsonb_each(node) child), '[]'::jsonb)
        when jsonb_typeof(node) = 'array' then node
        else '[]'::jsonb
      end
    ) as entry(value)
  )
  select coalesce(array_agg(distinct substring(node #>> '{}' from 'demo/[^[:space:]"?#]+')), '{}')
  from walk
  where jsonb_typeof(node) = 'string'
    and (node #>> '{}') like '%/demo-media/demo/%';
$fn$;

create or replace function demo.admin_state()
returns jsonb
language plpgsql
stable
security definer
set search_path = demo, public, pg_temp
as $fn$
declare
  v_current jsonb;
  v_version integer;
  v_published_at text;
  v_assembled jsonb;
begin
  select snapshot, version, snapshot->>'publishedAt'
    into v_current, v_version, v_published_at
  from publications
  where is_current
  order by version desc
  limit 1;

  if v_current is null then
    v_assembled := assemble_draft(1, to_char(clock_timestamp() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
  else
    v_assembled := assemble_draft(v_version, v_published_at);
  end if;

  return jsonb_build_object(
    'ok', true,
    'dirty', v_current is null or v_assembled is distinct from v_current,
    'changes', demo.change_summary(v_current, v_assembled),
    'published', (
      select jsonb_build_object(
        'version', version,
        'publishedAt', snapshot->>'publishedAt',
        'publisherEmail', publisher_email,
        'restoredFrom', restored_from,
        'changeSummary', change_summary,
        'isCurrent', true
      )
      from publications
      where is_current
      order by version desc
      limit 1
    ),
    'history', coalesce((
      select jsonb_agg(jsonb_build_object(
        'version', version,
        'publishedAt', snapshot->>'publishedAt',
        'publisherEmail', publisher_email,
        'restoredFrom', restored_from,
        'changeSummary', change_summary,
        'isCurrent', is_current
      ) order by version desc)
      from publications
    ), '[]'::jsonb),
    'draft', jsonb_build_object(
      'profiles', coalesce((select jsonb_agg(jsonb_build_object('role', role, 'record', payload) order by role, sort_order, id) from profiles), '[]'::jsonb),
      'accounts', coalesce((select jsonb_agg(payload order by sort_order, id) from accounts), '[]'::jsonb),
      'trades', coalesce((select jsonb_agg(payload order by sort_order, id) from trades), '[]'::jsonb),
      'posts', coalesce((select jsonb_agg(payload order by sort_order, id) from posts), '[]'::jsonb),
      'clips', coalesce((select jsonb_agg(payload order by sort_order, id) from clips), '[]'::jsonb),
      'stories', coalesce((select jsonb_agg(payload order by sort_order, id) from stories), '[]'::jsonb),
      'achievements', coalesce((select jsonb_agg(payload order by sort_order, id) from achievements), '[]'::jsonb),
      'activity', coalesce((select jsonb_agg(payload order by sort_order, id) from activity), '[]'::jsonb),
      'conversations', coalesce((select jsonb_agg(payload order by sort_order, id) from conversations), '[]'::jsonb),
      'messages', coalesce((select jsonb_agg(payload order by sort_order, id) from messages), '[]'::jsonb),
      'rooms', coalesce((select jsonb_agg(payload order by sort_order, id) from rooms), '[]'::jsonb),
      'channels', coalesce((select jsonb_agg(payload order by sort_order, id) from room_channels), '[]'::jsonb),
      'memberships', coalesce((select jsonb_agg(payload order by sort_order, profile_id) from room_memberships), '[]'::jsonb),
      'roomMessages', coalesce((select jsonb_agg(payload order by sort_order, id) from room_messages), '[]'::jsonb),
      'checkIns', coalesce((select jsonb_agg(payload order by sort_order, id) from check_ins), '[]'::jsonb),
      'payouts', coalesce((select jsonb_agg(payload order by sort_order, id) from payouts), '[]'::jsonb),
      'vaultFolders', coalesce((select jsonb_agg(payload order by sort_order, id) from vault_folders), '[]'::jsonb),
      'vaultItems', coalesce((select jsonb_agg(payload order by sort_order, id) from vault_items), '[]'::jsonb)
    )
  );
end;
$fn$;

create or replace function demo.admin_reorder(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = demo, pg_temp
as $fn$
declare
  v_entity text := p_payload->>'entity';
  v_item jsonb;
  v_index integer := 0;
  v_id text;
begin
  if v_entity not in ('account', 'vault_folder', 'vault_item', 'post', 'clip', 'achievement') then
    return jsonb_build_object('ok', false, 'error', 'This list cannot be reordered.');
  end if;

  for v_item in select value from jsonb_array_elements(coalesce(p_payload->'ids', '[]'::jsonb))
  loop
    v_id := trim(both '"' from v_item::text);
    if v_entity = 'account' then
      update accounts set sort_order = v_index where id = v_id;
    elsif v_entity = 'vault_folder' then
      update vault_folders set sort_order = v_index where id = v_id;
    elsif v_entity = 'vault_item' then
      update vault_items set sort_order = v_index where id = v_id;
    elsif v_entity = 'post' then
      update posts set sort_order = v_index where id = v_id;
    elsif v_entity = 'clip' then
      update clips set sort_order = v_index where id = v_id;
    elsif v_entity = 'achievement' then
      update achievements set sort_order = v_index where id = v_id;
    end if;
    v_index := v_index + 1;
  end loop;
  return admin_state();
end;
$fn$;

create or replace function demo.admin_publish(p_restored_from integer default null)
returns jsonb
language plpgsql
security definer
set search_path = demo, public, pg_temp
as $fn$
declare
  v_errors text[];
  v_next integer;
  v_at text;
  v_snapshot jsonb;
  v_previous jsonb;
  v_summary jsonb;
  v_email text;
begin
  lock table publications in exclusive mode;
  select snapshot into v_previous from publications where is_current order by version desc limit 1;
  v_next := coalesce((select max(version) from publications), 0) + 1;
  v_at := to_char(clock_timestamp() at time zone 'utc', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  v_snapshot := assemble_draft(v_next, v_at);
  v_errors := validate_snapshot(v_snapshot);
  if coalesce(array_length(v_errors, 1), 0) > 0 then
    return jsonb_build_object('ok', false, 'errors', to_jsonb(v_errors));
  end if;
  v_summary := demo.change_summary(v_previous, v_snapshot);
  if p_restored_from is not null then
    v_summary := v_summary || jsonb_build_object(
      'restoredFrom', p_restored_from,
      'lines', coalesce(v_summary->'lines', '[]'::jsonb) || jsonb_build_array(format('Restored version %s', p_restored_from))
    );
  end if;
  select email into v_email from auth.users where id = auth.uid();
  update publications set is_current = false where is_current;
  insert into publications (version, schema_version, published_at, snapshot, is_current, published_by, publisher_email, restored_from, change_summary)
  values (v_next, 1, clock_timestamp(), v_snapshot, true, auth.uid(), v_email, p_restored_from, v_summary);
  return admin_state() || jsonb_build_object('publishedVersion', v_next);
end;
$fn$;

create or replace function public.rpc_v1_admin_demo_media_refs()
returns text[]
language plpgsql
security definer
set search_path = demo, public, pg_temp
as $fn$
begin
  if auth.uid() is null or not exists (select 1 from public.admin_users where user_id = auth.uid()) then
    raise exception 'forbidden' using errcode = '42501';
  end if;
  return demo.referenced_media_paths();
end;
$fn$;

revoke all on function demo.json_id_diff(jsonb, jsonb) from public, anon, authenticated;
revoke all on function demo.change_summary(jsonb, jsonb) from public, anon, authenticated;
revoke all on function demo.referenced_media_paths() from public, anon, authenticated;
revoke all on function public.rpc_v1_admin_demo_media_refs() from public, anon;
grant execute on function public.rpc_v1_admin_demo_media_refs() to authenticated;

comment on function public.rpc_v1_admin_demo_media_refs() is
  'Admin-only list of demo-media object paths still referenced by the draft or any published version.';
