-- Feed bootstrap: load bidirectional block peers once per RPC (cand CTE hot path).
-- Replaces per-row users_have_active_block() in candidate/story filters (same semantics).
-- Run EXPLAIN (no ANALYZE) before/after: loadtest/diagnostics/feed_bootstrap_explain.sql

create index if not exists user_blocks_blocker_id_idx
  on public.user_blocks (blocker_id);

do $mig$
declare
  src text;
  updated text;
begin
  select pg_get_functiondef(p.oid)
  into src
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname = 'rpc_v1_feed_bootstrap'
    and pg_get_function_identity_arguments(p.oid) =
      'p_scope text, p_content_filter text, p_limit integer, p_cursor text';

  if src is null then
    raise exception 'rpc_v1_feed_bootstrap was not found';
  end if;

  if position('v_block_peers uuid[]' in src) > 0
     and position('get_active_block_peer_ids()' in src) > 0
     and position('users_have_active_block(v_uid,' in src) = 0 then
    return;
  end if;

  if (length(src) - length(replace(src, 'users_have_active_block(v_uid,', '')))
       / length('users_have_active_block(v_uid,') <> 5 then
    raise exception 'rpc_v1_feed_bootstrap expected 5 per-row block checks, found %',
      (length(src) - length(replace(src, 'users_have_active_block(v_uid,', '')))
        / length('users_have_active_block(v_uid,');
  end if;

  if position(
    E'  if v_uid is not null then\n    select coalesce(array_agg(f.following_id), ''{}''::uuid[])\n    into v_following\n    from public.followers f\n    where f.follower_id = v_uid;\n  end if;\n\n  if v_scope = ''following'' and cardinality(v_following) = 0 then'
    in src
  ) = 0 then
    raise exception 'rpc_v1_feed_bootstrap following-load anchor not found';
  end if;

  if position('v_following uuid[] := ''{}''::uuid[];' in src) = 0 then
    raise exception 'rpc_v1_feed_bootstrap v_following declare anchor not found';
  end if;

  updated := src;

  if position('v_block_peers uuid[]' in updated) = 0 then
    updated := replace(
      updated,
      'v_following uuid[] := ''{}''::uuid[];',
      E'v_following uuid[] := ''{}''::uuid[];\n  v_block_peers uuid[] := ''{}''::uuid[];'
    );
    if position('v_block_peers uuid[]' in updated) = 0 then
      raise exception 'rpc_v1_feed_bootstrap v_block_peers declare patch failed';
    end if;
  end if;

  if position('get_active_block_peer_ids()' in updated) = 0 then
    updated := replace(
      updated,
      E'  if v_uid is not null then\n    select coalesce(array_agg(f.following_id), ''{}''::uuid[])\n    into v_following\n    from public.followers f\n    where f.follower_id = v_uid;\n  end if;\n\n  if v_scope = ''following'' and cardinality(v_following) = 0 then',
      E'  if v_uid is not null then\n    select coalesce(array_agg(f.following_id), ''{}''::uuid[])\n    into v_following\n    from public.followers f\n    where f.follower_id = v_uid;\n  end if;\n\n  if not v_guest and v_uid is not null then\n    select public.get_active_block_peer_ids() into v_block_peers;\n  end if;\n\n  if v_scope = ''following'' and cardinality(v_following) = 0 then'
    );
    if position('get_active_block_peer_ids()' in updated) = 0 then
      raise exception 'rpc_v1_feed_bootstrap block peer load patch failed';
    end if;
  end if;

  updated := replace(
    updated,
    'and not public.users_have_active_block(v_uid, p.user_id)',
    'and (v_guest or not (p.user_id = any (v_block_peers)))'
  );
  updated := replace(
    updated,
    'and not public.users_have_active_block(v_uid, pp.user_id)',
    'and (v_guest or not (pp.user_id = any (v_block_peers)))'
  );
  updated := replace(
    updated,
    'and not public.users_have_active_block(v_uid, ap.user_id)',
    'and (v_guest or not (ap.user_id = any (v_block_peers)))'
  );
  updated := replace(
    updated,
    'and not public.users_have_active_block(v_uid, r.user_id)',
    'and (v_guest or not (r.user_id = any (v_block_peers)))'
  );
  updated := replace(
    updated,
    'or not public.users_have_active_block(v_uid, s.user_id)',
    'or v_guest or not (s.user_id = any (v_block_peers))'
  );

  if updated = src then
    raise exception 'rpc_v1_feed_bootstrap block peer patch made no changes';
  end if;

  if position('security definer' in lower(updated)) > 0 then
    raise exception 'rpc_v1_feed_bootstrap must stay security invoker';
  end if;

  if position('users_have_active_block(v_uid,' in updated) > 0 then
    raise exception 'rpc_v1_feed_bootstrap still uses per-row users_have_active_block';
  end if;

  if position('get_active_block_peer_ids()' in updated) = 0 then
    raise exception 'rpc_v1_feed_bootstrap missing get_active_block_peer_ids';
  end if;

  execute updated;
end
$mig$;

comment on function public.rpc_v1_feed_bootstrap(text, text, integer, text) is
  'Backend V2 Feed bootstrap — excludes blocked authors via get_active_block_peer_ids (bidirectional user_blocks).';
