#!/usr/bin/env node
/**
 * A/B/C benchmark: trade-reel lookup in rpc_v1_feed_bootstrap (embedded PG, staging only).
 *
 * 1. baseline lateral (no composite index)
 * 2. baseline lateral + reels(trade_id, created_at desc, id desc) partial index
 * 3. page-scoped batched DISTINCT ON + composite index + post-only guards
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { createHash } from "node:crypto"
import EmbeddedPostgres from "embedded-postgres"
import pg from "pg"
import { buildProductionShapedBody } from "./lib/feed-bootstrap-production-body.mjs"
import {
  applyBaselineTradeReelLookup,
  applyBatchedTradeReelLookup,
  COMPOSITE_INDEX_SQL,
  DROP_COMPOSITE_INDEX_SQL,
} from "./lib/feed-trade-reel-items-patch.mjs"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "../../..")
const { Client } = pg

const VIEWER = "aaaaaaaa-aaaa-4aaa-8aaa-000000000040"
const LIM = 8
const WARMUP = 2
const ITERS = 7
const PORT = 55453

const VARIANTS = [
  { id: "baseline_lateral", useCompositeIndex: false, batched: false },
  { id: "lateral_with_composite_index", useCompositeIndex: true, batched: false },
  { id: "batched_with_composite_index", useCompositeIndex: true, batched: true },
]

const SCENARIOS = [
  { id: "reel_only", scope: "following", filter: "reels", label: "reel-only first page" },
  { id: "mixed", scope: "following", filter: "all", label: "mixed first page" },
  { id: "trade_heavy", scope: "following", filter: "trades", label: "trade-heavy (posts only)" },
]

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
  out.push({
    path: [...trail, type].join(" > "),
    actual_ms: node["Actual Total Time"] ?? 0,
    loops: node["Actual Loops"] ?? 1,
    rows: node["Actual Rows"] ?? 0,
    index_name: node["Index Name"] ?? null,
    relation: node["Relation Name"] ?? null,
  })
  for (const c of node.Plans ?? []) walkPlan(c, [...trail, type], out)
}

async function explainMs(client, sql, params = []) {
  const { rows } = await client.query(`explain (analyze, buffers, format json) ${sql}`, params)
  const rootPlan = rows[0]["QUERY PLAN"][0]
  const nodes = []
  walkPlan(rootPlan.Plan, [], nodes)
  const reelNodes = nodes.filter((n) => n.relation === "reels")
  return {
    execution_ms: rootPlan["Execution Time"],
    planning_ms: rootPlan["Planning Time"],
    reel_index_hits: reelNodes.map((n) => n.index_name).filter(Boolean),
    top_reel: reelNodes.sort((a, b) => b.actual_ms - a.actual_ms)[0] ?? null,
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

function jsonHash(value) {
  const clone = structuredClone(value)
  if (clone?.meta && typeof clone.meta === "object") {
    delete clone.meta.server_time
  }
  return createHash("sha256").update(JSON.stringify(clone)).digest("hex")
}

function itemsHash(payload) {
  return createHash("sha256")
    .update(JSON.stringify(payload?.data?.items ?? []))
    .digest("hex")
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

async function installBenchmarkTradePayload(client) {
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
    ) returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
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
        'ticker', v_trade.ticker,
        'direction', v_trade.direction,
        'pnl', v_trade.pnl,
        'rr', v_trade.rr,
        'participating_account_modes', public.copy_trade_public_participating_account_modes_json(v_trade),
        'reels', case
          when p_reel.id is null or coalesce(p_reel.visibility, 'public') <> 'public' then null
          else jsonb_build_object(
            'id', p_reel.id,
            'user_id', p_reel.user_id,
            'video_url', p_reel.video_url,
            'thumbnail_url', p_reel.thumbnail_url,
            'duration_seconds', p_reel.duration_seconds,
            'trade_id', p_reel.trade_id,
            'visibility', p_reel.visibility,
            'created_at', p_reel.created_at
          )
        end
      );
    end;
    $$;
    grant execute on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) to authenticated;
  `)
}

async function installRpc(client, { batched }) {
  let body = buildProductionShapedBody()
  body = applyBaselineTradeReelLookup(body)
  await client.query(`
    create or replace function public.rpc_v1_feed_bootstrap(
      p_scope text default 'following',
      p_content_filter text default 'all',
      p_limit integer default 8,
      p_cursor text default null
    )
    returns jsonb
    language plpgsql
    stable
    set search_path to public
    as $function$ ${body} $function$;
  `)
  await client.query(
    fs.readFileSync(
      path.join(root, "supabase/migrations/20261027140000_feed_following_cand_per_followee.sql"),
      "utf8"
    )
  )
  if (!batched) return

  const { rows } = await client.query(`
    select pg_get_functiondef(p.oid) as def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_v1_feed_bootstrap'
      and pg_get_function_identity_arguments(p.oid) = 'p_scope text, p_content_filter text, p_limit integer, p_cursor text'
  `)
  const def = rows[0]?.def
  if (!def) throw new Error("rpc_v1_feed_bootstrap missing after cand migration")
  const parts = def.split("$function$")
  if (parts.length < 3) throw new Error("could not parse rpc_v1_feed_bootstrap body")
  const patched = applyBatchedTradeReelLookup(parts[1])
  await client.query(`
    create or replace function public.rpc_v1_feed_bootstrap(
      p_scope text default 'following',
      p_content_filter text default 'all',
      p_limit integer default 8,
      p_cursor text default null
    )
    returns jsonb
    language plpgsql
    stable
    set search_path to public
    as $function$ ${patched} $function$;
  `)
}

async function measureIsolatedTradeReelJoin(client, batched, viewerId) {
  const pageCte = `
    select 'post'::text as kind, p.id
    from public.posts p
    where p.user_id in (
      select f.following_id from public.followers f where f.follower_id = $1::uuid
    )
    order by p.created_at desc, p.id desc
    limit ${LIM}
  `
  const lateralSql = `
    with page as (
      select kind, id from (${pageCte}) pg
    )
    select count(*)::int
    from page pg
    left join public.posts p on pg.kind = 'post' and p.id = pg.id
    left join lateral (
      select r.id
      from public.reels r
      where r.trade_id = coalesce(p.trade_id, p.id)
      order by r.created_at desc
      limit 1
    ) tr on pg.kind = 'post'
  `
  const batchedSql = `
    with page as (
      select kind, id from (${pageCte}) pg
    ),
    post_page_trade_keys as (
      select pg.id as post_id, coalesce(p.trade_id, p.id) as trade_key
      from page pg
      inner join public.posts p on pg.kind = 'post' and p.id = pg.id
    ),
    page_latest_trade_reels as (
      select distinct on (r.trade_id) r.id, r.trade_id
      from public.reels r
      where r.trade_id in (select trade_key from post_page_trade_keys)
      order by r.trade_id, r.created_at desc, r.id desc
    )
    select count(*)::int
    from page pg
    left join public.posts p on pg.kind = 'post' and p.id = pg.id
    left join post_page_trade_keys ptk on ptk.post_id = p.id
    left join page_latest_trade_reels tr
      on pg.kind = 'post' and p.id is not null and tr.trade_id = ptk.trade_key
  `
  return timedMedian(client, () =>
    explainMs(client, batched ? batchedSql : lateralSql, [viewerId])
  )
}

async function runVariant(client, variant, baselineHashesByScenario) {
  const scenarioResults = []

  for (const scenario of SCENARIOS) {
    const fullRpc = await timedMedian(client, () =>
      explainMs(
        client,
        `select public.rpc_v1_feed_bootstrap($1, $2, $3, null)`,
        [scenario.scope, scenario.filter, LIM]
      )
    )

    const { rows: jsonRows } = await client.query(
      `select public.rpc_v1_feed_bootstrap($1, $2, $3, null) as j`,
      [scenario.scope, scenario.filter, LIM]
    )
    const payload = jsonRows[0]?.j
    const items = payload?.data?.items ?? []
    const pageMeta = {
      returned: items.length,
      post_items: items.filter((i) => i.kind === "post").length,
      reel_items: items.filter((i) => i.kind === "reel").length,
      posts_with_embedded_reel: items.filter(
        (i) => i.kind === "post" && i.payload?.trades?.reels?.id
      ).length,
    }
    const hash = jsonHash(payload)
    const itemsOnlyHash = itemsHash(payload)

    scenarioResults.push({
      scenario: scenario.id,
      label: scenario.label,
      page_meta: pageMeta,
      full_rpc_explain_median_ms: fullRpc.median_ms,
      full_rpc_top_reel_node: fullRpc.last.top_reel,
      json_sha256: hash,
      items_sha256: itemsOnlyHash,
      items_match_baseline:
        variant.id === "baseline_lateral"
          ? true
          : itemsOnlyHash === baselineHashesByScenario[scenario.id],
    })
  }

  const isolated = await measureIsolatedTradeReelJoin(client, variant.batched, VIEWER)

  return {
    variant: variant.id,
    composite_index: variant.useCompositeIndex,
    lookup_strategy: variant.batched ? "batched_distinct_on" : "lateral_per_post",
    scenarios: scenarioResults,
    isolated_trade_reel_join_on_trades_page: {
      median_ms: isolated.median_ms,
      top_reel_node: isolated.last.top_reel,
      index_hits_sample: isolated.last.reel_index_hits.slice(0, 4),
    },
  }
}

async function main() {
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-trade-reel-lookup-bench"),
    port: PORT,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()

  const client = new Client({
    host: "127.0.0.1",
    port: PORT,
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
    await installBenchmarkTradePayload(client)

    await client.query("begin")
    await client.query(`select set_config('bench.scale', 'large', true)`)
    await client.query(read("seed/seed_synthetic.sql"))
    await client.query(read("seed/seed_post_trade_reel_links.sql"))
    await client.query("commit")

    const counts = (
      await client.query(`
        select
          (select count(*)::bigint from public.posts) as posts,
          (select count(*)::bigint from public.posts where trade_id is not null) as posts_with_trade,
          (select count(*)::bigint from public.reels where trade_id is not null) as trade_reels
      `)
    ).rows[0]

    const variantRuns = []
    const baselineHashesByScenario = {}
    for (const variant of VARIANTS) {
      await client.query("reset role")
      await client.query(DROP_COMPOSITE_INDEX_SQL)
      if (variant.useCompositeIndex) {
        await client.query(COMPOSITE_INDEX_SQL)
        await client.query(`analyze public.reels`)
      }
      await installRpc(client, variant)

      await client.query("begin")
      await client.query("set local role authenticated")
      await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [VIEWER])

      const run = await runVariant(client, variant, baselineHashesByScenario)
      await client.query("rollback")

      if (variant.id === "baseline_lateral") {
        for (const s of run.scenarios) baselineHashesByScenario[s.scenario] = s.items_sha256
      }
      variantRuns.push(run)
    }

    const report = {
      generated_at: new Date().toISOString(),
      environment: "embedded-postgres-18-staging-benchmark",
      viewer: VIEWER,
      scale: "large",
      iterations: ITERS,
      warmup: WARMUP,
      composite_index_ddl: COMPOSITE_INDEX_SQL.trim(),
      seed_counts: counts,
      variants: variantRuns,
      recommendation: null,
    }

    const base = variantRuns.find((v) => v.variant === "baseline_lateral")
    const latIdx = variantRuns.find((v) => v.variant === "lateral_with_composite_index")
    const batched = variantRuns.find((v) => v.variant === "batched_with_composite_index")
    const tradeHeavy = (v) => v.scenarios.find((s) => s.scenario === "trade_heavy")

    const isoBase = base?.isolated_trade_reel_join_on_trades_page?.median_ms ?? 0
    const isoLat = latIdx?.isolated_trade_reel_join_on_trades_page?.median_ms ?? 0
    const isoBatch = batched?.isolated_trade_reel_join_on_trades_page?.median_ms ?? 0
    const rpcBase = tradeHeavy(base)?.full_rpc_explain_median_ms ?? 0
    const rpcBatch = tradeHeavy(batched)?.full_rpc_explain_median_ms ?? 0

    const allItemsMatch = variantRuns.every((v) =>
      v.scenarios.every((s) => s.items_match_baseline !== false)
    )

    const rpcReel = (v) => v.scenarios.find((s) => s.scenario === "reel_only")?.full_rpc_explain_median_ms
    const rpcMixed = (v) => v.scenarios.find((s) => s.scenario === "mixed")?.full_rpc_explain_median_ms

    report.recommendation = {
      items_json_parity_all_scenarios: allItemsMatch,
      isolated_join_ms: { baseline: isoBase, lateral_plus_index: isoLat, batched_plus_index: isoBatch },
      full_rpc_median_ms: {
        reel_only: {
          baseline: rpcReel(base),
          lateral_plus_index: rpcReel(latIdx),
          batched: rpcReel(batched),
        },
        mixed: {
          baseline: rpcMixed(base),
          lateral_plus_index: rpcMixed(latIdx),
          batched: rpcMixed(batched),
        },
        trade_heavy: {
          baseline: rpcBase,
          lateral_plus_index: tradeHeavy(latIdx)?.full_rpc_explain_median_ms,
          batched: rpcBatch,
        },
      },
      note_timing:
        "Variants run sequentially on one embedded cluster; later variants may see warmer buffer cache. Isolated join timings control for lookup strategy only.",
      suggested_path:
        allItemsMatch && rpcBatch < rpcBase * 0.75
          ? "Adopt page-scoped batched DISTINCT ON (newest reel per trade_id) + partial composite index in a feed RPC migration. Index alone does not materially change lateral cost."
          : isoLat < isoBase * 0.9
            ? "Composite index gives modest lateral improvement; prefer batched lookup for trade-heavy pages."
            : "Re-run with per-variant cold cache if comparing absolute RPC ms; batched lookup still recommended when items stage dominates.",
    }

    const out = path.join(__dirname, "artifacts/feed_trade_reel_lookup_benchmark_report.json")
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
