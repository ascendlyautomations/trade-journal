#!/usr/bin/env node
/**
 * Isolate costs inside rpc_v1_feed_bootstrap `items` stage (embedded PG, EXPLAIN ANALYZE BUFFERS).
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import EmbeddedPostgres from "embedded-postgres"
import pg from "pg"
import { buildProductionShapedBody } from "./lib/feed-bootstrap-production-body.mjs"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "../../..")
const { Client } = pg

const VIEWER = "aaaaaaaa-aaaa-4aaa-8aaa-000000000040"
const LIM = 8
const LIM_PLUS = LIM + 1
const WARMUP = 1
const ITERS = 5

function read(rel) {
  return fs.readFileSync(path.join(__dirname, rel), "utf8")
}

function median(nums) {
  const s = [...nums].sort((a, b) => a - b)
  const m = Math.floor(s.length / 2)
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}

function walkPlan(node, trail, out) {
  if (!node) return
  const type = node["Node Type"] ?? "?"
  const label = [...trail, type].join(" > ")
  out.push({
    path: label,
    node_type: type,
    actual_ms: node["Actual Total Time"] ?? 0,
    actual_loops: node["Actual Loops"] ?? 1,
    rows: node["Actual Rows"] ?? 0,
    shared_hit: node["Shared Hit Blocks"] ?? 0,
    shared_read: node["Shared Read Blocks"] ?? 0,
    filter: node.Filter ?? null,
    index_name: node["Index Name"] ?? null,
    relation: node["Relation Name"] ?? null,
    function_name: node["Function Name"] ?? null,
  })
  for (const c of node.Plans ?? []) walkPlan(c, [...trail, type], out)
}

function topHotspots(planRoot, limit = 12) {
  const nodes = []
  walkPlan(planRoot, [], nodes)
  return nodes
    .filter((n) => n.actual_ms > 0.01)
    .sort((a, b) => b.actual_ms - a.actual_ms)
    .slice(0, limit)
}

async function explainAnalyze(client, sql, params = []) {
  const { rows } = await client.query(`explain (analyze, buffers, verbose, format json) ${sql}`, params)
  const root = rows[0]["QUERY PLAN"][0]
  return {
    execution_ms: root["Execution Time"],
    planning_ms: root["Planning Time"],
    plan: root.Plan,
    hotspots: topHotspots(root.Plan),
  }
}

async function timedMedian(client, fn) {
  for (let i = 0; i < WARMUP; i++) await fn()
  const ms = []
  let last = null
  for (let i = 0; i < ITERS; i++) {
    last = await fn()
    ms.push(last.execution_ms)
  }
  return { median_ms: Math.round(median(ms) * 100) / 100, last }
}

function pageCteSql() {
  return `
    with ctx as (
      select
        $1::uuid as v_uid,
        coalesce(
          (select array_agg(f.following_id) from public.followers f where f.follower_id = $1),
          '{}'::uuid[]
        ) as v_following,
        coalesce((select public.get_active_block_peer_ids()), '{}'::uuid[]) as v_block_peers,
        false as v_guest,
        true as v_include_trades,
        true as v_include_posts,
        true as v_include_achievements,
        true as v_include_reels,
        null::timestamptz as v_cursor_ts,
        null::text as v_cursor_kind,
        null::uuid as v_cursor_id,
        null::int as v_cursor_kind_rank,
        false as v_cursor_legacy
    ),
    cand as (
      select kind, id, author_id, created_at from (
        select * from (
          select kind, id, author_id, created_at from (
            select lat.kind, lat.id, lat.author_id, lat.created_at
            from ctx c, unnest(c.v_following) fid
            cross join lateral (
              select 'post'::text as kind, p.id, p.user_id as author_id, p.created_at
              from public.posts p, ctx c2
              where c2.v_include_trades and p.user_id = fid and p.user_id is distinct from c2.v_uid
                and not (p.user_id = any (c2.v_block_peers))
                and public._v1_feed_before_cursor(
                  p.created_at, 'post', p.id,
                  c2.v_cursor_ts, c2.v_cursor_kind, c2.v_cursor_id, c2.v_cursor_kind_rank, c2.v_cursor_legacy)
              order by p.created_at desc, p.id desc limit ${LIM_PLUS}
            ) lat
          ) x order by created_at desc, id desc limit ${LIM_PLUS}
        ) trades_c
        union all
        select * from (
          select kind, id, author_id, created_at from (
            select lat.kind, lat.id, lat.author_id, lat.created_at
            from ctx c, unnest(c.v_following) fid
            cross join lateral (
              select 'profile_post'::text as kind, pp.id, pp.user_id as author_id, pp.created_at
              from public.profile_posts pp, ctx c2
              where c2.v_include_posts and pp.user_id = fid and pp.user_id is distinct from c2.v_uid
                and not (pp.user_id = any (c2.v_block_peers))
                and public._v1_feed_before_cursor(
                  pp.created_at, 'profile_post', pp.id,
                  c2.v_cursor_ts, c2.v_cursor_kind, c2.v_cursor_id, c2.v_cursor_kind_rank, c2.v_cursor_legacy)
              order by pp.created_at desc, pp.id desc limit ${LIM_PLUS}
            ) lat
          ) x order by created_at desc, id desc limit ${LIM_PLUS}
        ) posts_c
        union all
        select * from (
          select kind, id, author_id, created_at from (
            select lat.kind, lat.id, lat.author_id, lat.created_at
            from ctx c, unnest(c.v_following) fid
            cross join lateral (
              select 'achievement_post'::text as kind, ap.id, ap.user_id as author_id, ap.created_at
              from public.achievement_posts ap
              join public.achievements a on a.id = ap.achievement_id, ctx c2
              where c2.v_include_achievements and ap.user_id = fid and ap.user_id is distinct from c2.v_uid
                and not (ap.user_id = any (c2.v_block_peers)) and coalesce(a.is_public, true)
                and public._v1_feed_before_cursor(
                  ap.created_at, 'achievement_post', ap.id,
                  c2.v_cursor_ts, c2.v_cursor_kind, c2.v_cursor_id, c2.v_cursor_kind_rank, c2.v_cursor_legacy)
              order by ap.created_at desc, ap.id desc limit ${LIM_PLUS}
            ) lat
          ) x order by created_at desc, id desc limit ${LIM_PLUS}
        ) ach_c
        union all
        select * from (
          select kind, id, author_id, created_at from (
            select lat.kind, lat.id, lat.author_id, lat.created_at
            from ctx c, unnest(c.v_following) fid
            cross join lateral (
              select 'reel'::text as kind, r.id, r.user_id as author_id, r.created_at
              from public.reels r, ctx c2
              where c2.v_include_reels and r.user_id = fid and r.user_id is distinct from c2.v_uid
                and not (r.user_id = any (c2.v_block_peers))
                and public._v1_feed_before_cursor(
                  r.created_at, 'reel', r.id,
                  c2.v_cursor_ts, c2.v_cursor_kind, c2.v_cursor_id, c2.v_cursor_kind_rank, c2.v_cursor_legacy)
                and r.trade_id is null
              order by r.created_at desc, r.id desc limit ${LIM_PLUS}
            ) lat
          ) x order by created_at desc, id desc limit ${LIM_PLUS}
        ) reels_c
      ) merged
    ),
    ranked as (
      select row_number() over (
        order by c.created_at desc, public._v1_feed_kind_rank(c.kind) desc, c.id desc
      ) rn, c.*
      from cand c
    )
    select kind, id, author_id, created_at from ranked where rn <= ${LIM}
  `
}

/** Cand: posts branch only (same ids eventually on page). */
function candPostsBranchSql() {
  return `
    with ctx as (
      select
        $1::uuid as v_uid,
        coalesce(
          (select array_agg(f.following_id) from public.followers f where f.follower_id = $1),
          '{}'::uuid[]
        ) as v_following,
        coalesce((select public.get_active_block_peer_ids()), '{}'::uuid[]) as v_block_peers,
        true as v_include_trades,
        null::timestamptz as v_cursor_ts,
        null::text as v_cursor_kind,
        null::uuid as v_cursor_id,
        null::int as v_cursor_kind_rank,
        false as v_cursor_legacy
    )
    select count(*)::int from (
      select lat.id
      from ctx c, unnest(c.v_following) fid
      cross join lateral (
        select p.id
        from public.posts p, ctx c2
        where c2.v_include_trades and p.user_id = fid
          and not (p.user_id = any (c2.v_block_peers))
          and public._v1_feed_before_cursor(
            p.created_at, 'post', p.id,
            c2.v_cursor_ts, c2.v_cursor_kind, c2.v_cursor_id, c2.v_cursor_kind_rank, c2.v_cursor_legacy)
        order by p.created_at desc, p.id desc limit ${LIM_PLUS}
      ) lat
    ) q
  `
}

async function installPayloadVariants(client) {
  const payloadBody = `
    declare v_trade public.trades%rowtype;
    begin
      if p_trade_id is null then return null; end if;
      select * into v_trade from public.trades t where t.id = p_trade_id;
      if v_trade.id is null then return null; end if;
      if public.viewer_has_block_with(v_trade.user_id) then return null; end if;
      if not public.profile_is_visible_to_viewer(v_trade.user_id) then return null; end if;
      if auth.uid() is distinct from v_trade.user_id
         and not (coalesce(v_trade.is_public, false) and public.profile_viewer_can_view_trades(v_trade.user_id))
      then return null; end if;
      return jsonb_build_object(
        'user_id', v_trade.user_id,
        'is_public', v_trade.is_public,
        'participating_account_modes', public.copy_trade_public_participating_account_modes_json(v_trade)
      );
    end;
  `
  await client.query(`
    alter table public.trades add column if not exists public_description text;
    alter table public.profiles add column if not exists is_hidden_from_community boolean not null default false;
    create or replace function public.copy_trade_public_participating_account_modes_json(p_trade public.trades)
    returns jsonb language sql stable as $$ select '[]'::jsonb $$;
    create or replace function public.profile_is_visible_to_viewer(p_profile_id uuid)
    returns boolean language sql stable security definer set search_path = public as $$
      select p_profile_id is not null and exists (
        select 1 from public.profiles p where p.id = p_profile_id
          and (p.id = auth.uid() or coalesce(p.is_hidden_from_community, false) = false));
    $$;
    create or replace function public.profile_viewer_can_view_trades(p_profile_id uuid)
    returns boolean language sql stable security definer set search_path = public as $$
      select p_profile_id is not null and (
        p_profile_id = auth.uid()
        or exists (select 1 from public.profiles p where p.id = p_profile_id and coalesce(p.is_private, false) = false)
        or exists (select 1 from public.followers f where f.follower_id = auth.uid() and f.following_id = p_profile_id));
    $$;
    grant execute on function public.profile_is_visible_to_viewer(uuid) to anon, authenticated;
    grant execute on function public.profile_viewer_can_view_trades(uuid) to authenticated;
    create or replace function public._v1_feed_post_trade_payload(
      p_trade_id uuid, p_reel public.reels, p_guest boolean
    ) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp
    as $$ ${payloadBody} $$;
    grant execute on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) to authenticated;
  `)
}

async function installProdRls(client) {
  for (const stmt of [
    `drop policy if exists posts_select_visible on public.posts`,
    `drop policy if exists profile_posts_select_visible on public.profile_posts`,
    `drop policy if exists achievement_posts_select_visible on public.achievement_posts`,
    `drop policy if exists reels_select_visible on public.reels`,
  ]) {
    await client.query(stmt)
  }
  await client.query(
    fs.readFileSync(
      path.join(root, "supabase/migrations/20261027160000_feed_rls_block_peers_array.sql"),
      "utf8"
    )
  )
  await client.query(`grant select on all tables in schema public to anon, authenticated`)
}

async function installRpc(client) {
  const body = buildProductionShapedBody()
  await client.query(`
CREATE OR REPLACE FUNCTION public.rpc_v1_feed_bootstrap(
  p_scope text, p_content_filter text, p_limit integer, p_cursor text
)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO public AS $function$ ${body} $function$;`)
  await client.query(
    fs.readFileSync(
      path.join(root, "supabase/migrations/20261027140000_feed_following_cand_per_followee.sql"),
      "utf8"
    )
  )
}

async function runScenario(client, scenarioName, viewerId, pageSql, pageParams) {
  await client.query(`delete from _feed_page`)
  await client.query(
    `insert into _feed_page (rn, kind, id, author_id, created_at)
     select row_number() over ()::int, kind, id, author_id, created_at
     from (${pageSql}) page`,
    pageParams
  )

  const pageMeta = (
    await client.query(
      `select
          count(*)::int as page_rows,
          count(*) filter (where kind = 'post')::int as post_rows,
          count(*) filter (where kind = 'profile_post')::int as profile_post_rows,
          count(*) filter (where kind = 'achievement_post')::int as achievement_rows,
          count(*) filter (where kind = 'reel')::int as reel_rows
         from _feed_page`
    )
  ).rows[0]

  const hydratedRowsSql = `
       select
         pg.rn,
         pg.kind,
         pg.id as page_id,
         p.id as post_id,
         p.trade_id,
         tr.id as trade_reel_id
       from _feed_page pg
       left join public.posts p on pg.kind = 'post' and p.id = pg.id
       left join lateral (
         select r.id
         from public.reels r
         where pg.kind = 'post'
           and p.id is not null
           and r.trade_id = coalesce(p.trade_id, p.id)
         order by r.created_at desc
         limit 1
       ) tr on true
       left join public.profile_posts pp on pg.kind = 'profile_post' and pp.id = pg.id
       left join public.reels rl on pg.kind = 'reel' and rl.id = pg.id`

  const measures = {}

  measures.cand_discovery_full = await timedMedian(client, () =>
    explainAnalyze(client, `select count(*)::int from (${pageCteSql()}) page`, [viewerId])
  )

  measures["1_item_row_fetch_rls_only"] = await timedMedian(client, () =>
    explainAnalyze(
      client,
      `select count(*)::int from _feed_page pg
         left join public.posts p on pg.kind = 'post' and p.id = pg.id
         left join public.profile_posts pp on pg.kind = 'profile_post' and pp.id = pg.id
         left join public.reels rl on pg.kind = 'reel' and rl.id = pg.id`
    )
  )

  measures["2_joins_and_lateral"] = await timedMedian(client, () =>
    explainAnalyze(client, `select count(*)::int from (${hydratedRowsSql}) q`)
  )

  measures["2b_lateral_reel_post_only"] = await timedMedian(client, () =>
    explainAnalyze(
      client,
      `select count(*)::int from _feed_page pg
         join public.posts p on pg.kind = 'post' and p.id = pg.id
         left join lateral (
           select r.id from public.reels r
           where r.trade_id = coalesce(p.trade_id, p.id)
           order by r.created_at desc limit 1
         ) tr on true`
    )
  )

  measures["3_json_from_materialized_rows"] = await timedMedian(client, () =>
    explainAnalyze(
      client,
      `select coalesce(jsonb_agg(jsonb_build_object('kind', h.kind, 'id', h.page_id) order by h.rn), '[]'::jsonb)
         from (${hydratedRowsSql}) h`
    )
  )

  measures["3b_json_full_production_shape"] = await timedMedian(client, () =>
    explainAnalyze(
      client,
      `with authors as (
           select coalesce(jsonb_object_agg(p.id::text, jsonb_build_object(
             'username', p.username)), '{}'::jsonb) as map
           from public.profiles p
           where p.id in (select distinct author_id from _feed_page)
         )
         select coalesce(jsonb_agg(item order by rn), '[]'::jsonb)
         from (
           select pg.rn,
             case pg.kind
               when 'post' then jsonb_build_object(
                 'kind', 'post', 'id', p.id,
                 'payload', jsonb_build_object(
                   'trades', public._v1_feed_post_trade_payload(p.trade_id, tr, false)
                 )
               )
               when 'reel' then jsonb_build_object('kind', 'reel', 'id', rl.id)
             end as item
           from _feed_page pg
           cross join authors au
           left join public.posts p on pg.kind = 'post' and p.id = pg.id
           left join lateral (
             select r.* from public.reels r
             where r.trade_id = coalesce(p.trade_id, p.id)
             order by r.created_at desc limit 1
           ) tr on pg.kind = 'post'
           left join public.reels rl on pg.kind = 'reel' and rl.id = pg.id
         ) x where item is not null`
    )
  )

  measures["4_trade_payload_expansion"] = await timedMedian(client, () =>
    explainAnalyze(
      client,
      `select coalesce(sum(octet_length(j::text)), 0)::bigint
         from _feed_page pg
         join public.posts p on pg.kind = 'post' and p.id = pg.id
         left join lateral (
           select r.* from public.reels r
           where r.trade_id = coalesce(p.trade_id, p.id)
           order by r.created_at desc limit 1
         ) tr on true
         cross join lateral (select public._v1_feed_post_trade_payload(p.trade_id, tr, false) j) x`
    )
  )

  measures["4b_visibility_helpers_only"] = await timedMedian(client, () =>
    explainAnalyze(
      client,
      `select count(*)::int from _feed_page pg
         join public.posts p on pg.kind = 'post' and p.id = pg.id
         cross join lateral (select public.profile_is_visible_to_viewer(p.user_id)) v
         cross join lateral (select public.profile_viewer_can_view_trades(p.user_id)) t
         cross join lateral (select public.viewer_has_block_with(p.user_id)) b`
    )
  )

  measures["5_cand_posts_branch_reads"] = await timedMedian(client, () =>
    explainAnalyze(client, candPostsBranchSql(), [viewerId])
  )

  measures["5_items_posts_reread"] = await timedMedian(client, () =>
    explainAnalyze(
      client,
      `select count(*)::int from _feed_page pg
         join public.posts p on pg.kind = 'post' and p.id = pg.id`
    )
  )

  const summarize = (m) => ({
    median_ms: m.median_ms,
    top_hotspots: m.last.hotspots.slice(0, 8).map((h) => ({
      path: h.path,
      actual_ms: Math.round(h.actual_ms * 100) / 100,
      loops: h.actual_loops,
      rows: h.rows,
      shared_hit: h.shared_hit,
      relation: h.relation,
      index_name: h.index_name,
      function_name: h.function_name,
      filter: h.filter ? String(h.filter).slice(0, 140) : null,
    })),
  })

  return {
    scenario: scenarioName,
    page: pageMeta,
    measures: Object.fromEntries(Object.entries(measures).map(([k, v]) => [k, summarize(v)])),
    derived_ms: {
      cand_full: measures.cand_discovery_full.median_ms,
      row_fetch_rls_only: measures["1_item_row_fetch_rls_only"].median_ms,
      joins_lateral: measures["2_joins_and_lateral"].median_ms,
      lateral_reel_for_posts: measures["2b_lateral_reel_post_only"].median_ms,
      json_from_rows: measures["3_json_from_materialized_rows"].median_ms,
      json_full_shape: measures["3b_json_full_production_shape"].median_ms,
      trade_payload: measures["4_trade_payload_expansion"].median_ms,
      visibility_helpers: measures["4b_visibility_helpers_only"].median_ms,
      cand_posts_branch: measures["5_cand_posts_branch_reads"].median_ms,
      items_posts_reread: measures["5_items_posts_reread"].median_ms,
    },
  }
}

async function main() {
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-items-stage-isolation"),
    port: 55452,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()
  const client = new Client({
    host: "127.0.0.1",
    port: 55452,
    user: "postgres",
    password: "password",
    database: "postgres",
  })
  await client.connect()

  try {
    await client.query(`do $$ begin create role authenticated; exception when duplicate_object then null; end $$`)
    await client.query(`do $$ begin create role anon; exception when duplicate_object then null; end $$`)
    for (const f of [
      "init/01_schema.sql",
      "init/02_indexes.sql",
      "init/03_feed_helpers.sql",
      "init/04_feed_rpc_stubs.sql",
      "init/05_feed_rls_block_peers_test_extras.sql",
    ]) {
      await client.query(read(f))
    }
    await installProdRls(client)
    await installPayloadVariants(client)
    await installRpc(client)

    await client.query("begin")
    await client.query(`select set_config('bench.scale', 'large', true)`)
    await client.query(read("seed/seed_synthetic.sql"))
    await client.query("commit")

    await client.query("begin")
    await client.query("set local role authenticated")
    await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [VIEWER])

    await client.query(
      `create temp table _feed_page (
        rn int, kind text, id uuid, author_id uuid, created_at timestamptz
      ) on commit drop`
    )

    const tradeHeavyPageSql = `
      select 'post'::text as kind, p.id, p.user_id as author_id, p.created_at
      from public.posts p
      where p.user_id in (select f.following_id from public.followers f where f.follower_id = $1)
      order by p.created_at desc, p.id desc
      limit ${LIM}`

    const scenarios = [
      await runScenario(client, "natural_first_page", VIEWER, pageCteSql(), [VIEWER]),
      await runScenario(client, "trade_heavy_page", VIEWER, tradeHeavyPageSql, [VIEWER]),
    ]

    await client.query("rollback")

    const report = {
      generated_at: new Date().toISOString(),
      environment: "embedded-postgres-18",
      viewer: VIEWER,
      scale: "large",
      iterations: ITERS,
      scenarios,
    }

    const out = path.join(__dirname, "artifacts/feed_items_stage_isolation_report.json")
    fs.mkdirSync(path.dirname(out), { recursive: true })
    fs.writeFileSync(out, JSON.stringify(report, null, 2))
    console.log(JSON.stringify(report, null, 2))
  } finally {
    await client.end()
    await embedded.stop()
  }
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
