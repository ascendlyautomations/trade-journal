#!/usr/bin/env node
/**
 * Fair A/B: baseline lateral vs migration 20261027220000 batched lookup.
 * Alternating execution order + shared warm-up so buffer cache bias is reduced.
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { createHash } from "node:crypto"
import EmbeddedPostgres from "embedded-postgres"
import pg from "pg"
import { buildProductionShapedBody } from "./lib/feed-bootstrap-production-body.mjs"
import { applyBaselineTradeReelLookup } from "./lib/feed-trade-reel-items-patch.mjs"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "../../..")
const { Client } = pg

const VIEWER = "aaaaaaaa-aaaa-4aaa-8aaa-000000000040"
const LIM = 8
const WARMUP_ROUNDS = 4
const MEASURE_PAIRS = 10

const SCENARIOS = [
  { id: "reel_only", scope: "following", filter: "reels" },
  { id: "mixed", scope: "following", filter: "all" },
  { id: "trade_heavy", scope: "following", filter: "trades" },
]

function read(rel) {
  return fs.readFileSync(path.join(__dirname, rel), "utf8")
}

function median(nums) {
  const s = [...nums].sort((a, b) => a - b)
  const m = Math.floor(s.length / 2)
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}

function itemsHash(payload) {
  return createHash("sha256")
    .update(JSON.stringify(payload?.data?.items ?? []))
    .digest("hex")
}

async function explainMs(client, scope, filter) {
  const { rows } = await client.query(
    `explain (analyze, buffers, format json)
     select public.rpc_v1_feed_bootstrap($1, $2, $3, null)`,
    [scope, filter, LIM]
  )
  const plan = rows[0]["QUERY PLAN"][0]
  return plan["Execution Time"]
}

async function fetchRpc(client, scope, filter) {
  const { rows } = await client.query(
    `select public.rpc_v1_feed_bootstrap($1, $2, $3, null) as j`,
    [scope, filter, LIM]
  )
  return rows[0].j
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

async function installBaselineRpc(client) {
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
}

async function getRpcDef(client) {
  const { rows } = await client.query(`
    select pg_get_functiondef(p.oid) as def
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'rpc_v1_feed_bootstrap'
      and pg_get_function_identity_arguments(p.oid) = 'p_scope text, p_content_filter text, p_limit integer, p_cursor text'
  `)
  return rows[0]?.def
}

async function execRpcDef(client, def, viewerId) {
  await client.query("reset role")
  await client.query(def)
  await client.query("set local role authenticated")
  await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [viewerId])
}

async function main() {
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-trade-reel-fair-ab"),
    port: 55454,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()

  const client = new Client({
    host: "127.0.0.1",
    port: 55454,
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
    await installBaselineRpc(client)

    await client.query("begin")
    await client.query(`select set_config('bench.scale', 'large', true)`)
    await client.query(read("seed/seed_synthetic.sql"))
    await client.query(read("seed/seed_post_trade_reel_links.sql"))
    await client.query("commit")

    const baselineDef = await getRpcDef(client)

    await client.query(
      fs.readFileSync(
        path.join(root, "supabase/migrations/20261027220000_feed_bootstrap_batched_trade_reel_lookup.sql"),
        "utf8"
      )
    )
    const optimizedDef = await getRpcDef(client)

    if (!optimizedDef.includes("post_page_trade_keys")) {
      throw new Error("migration 20261027220000 did not apply batched lookup")
    }

    await client.query("begin")
    await client.query("set local role authenticated")
    await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [VIEWER])

    const parity = {}
    for (const sc of SCENARIOS) {
      await execRpcDef(client, baselineDef, VIEWER)
      const baseItems = itemsHash(await fetchRpc(client, sc.scope, sc.filter))
      await execRpcDef(client, optimizedDef, VIEWER)
      const optItems = itemsHash(await fetchRpc(client, sc.scope, sc.filter))
      parity[sc.id] = { match: baseItems === optItems, baseline: baseItems, optimized: optItems }
    }

    async function runVariant(def, sc) {
      await execRpcDef(client, def, VIEWER)
      return explainMs(client, sc.scope, sc.filter)
    }

    for (let w = 0; w < WARMUP_ROUNDS; w++) {
      const first = w % 2 === 0 ? "baseline" : "optimized"
      for (const sc of SCENARIOS) {
        if (first === "baseline") {
          await runVariant(baselineDef, sc)
          await runVariant(optimizedDef, sc)
        } else {
          await runVariant(optimizedDef, sc)
          await runVariant(baselineDef, sc)
        }
      }
    }

    const samples = {
      baseline: Object.fromEntries(SCENARIOS.map((s) => [s.id, []])),
      optimized: Object.fromEntries(SCENARIOS.map((s) => [s.id, []])),
    }

    for (let p = 0; p < MEASURE_PAIRS; p++) {
      const baselineFirst = p % 2 === 0
      for (const sc of SCENARIOS) {
        if (baselineFirst) {
          samples.baseline[sc.id].push(await runVariant(baselineDef, sc))
          samples.optimized[sc.id].push(await runVariant(optimizedDef, sc))
        } else {
          samples.optimized[sc.id].push(await runVariant(optimizedDef, sc))
          samples.baseline[sc.id].push(await runVariant(baselineDef, sc))
        }
      }
    }

    await client.query("rollback")

    const summarize = (arr) => ({
      median_ms: Math.round(median(arr) * 100) / 100,
      min_ms: Math.round(Math.min(...arr) * 100) / 100,
      max_ms: Math.round(Math.max(...arr) * 100) / 100,
      n: arr.length,
    })

    const report = {
      generated_at: new Date().toISOString(),
      environment: "embedded-postgres-18",
      migration: "20261027220000_feed_bootstrap_batched_trade_reel_lookup",
      methodology: {
        warmup_rounds: WARMUP_ROUNDS,
        measure_pairs: MEASURE_PAIRS,
        order: "alternate baseline-first vs optimized-first per pair index",
        shared_index: "reels_trade_id_created_at_id_idx on both variants",
      },
      items_json_parity: parity,
      results: {
        baseline_lateral: Object.fromEntries(
          SCENARIOS.map((s) => [s.id, summarize(samples.baseline[s.id])])
        ),
        batched_migration: Object.fromEntries(
          SCENARIOS.map((s) => [s.id, summarize(samples.optimized[s.id])])
        ),
      },
      deltas_median_ms: Object.fromEntries(
        SCENARIOS.map((s) => {
          const b = median(samples.baseline[s.id])
          const o = median(samples.optimized[s.id])
          return [s.id, { saved: Math.round((b - o) * 100) / 100, pct: Math.round((1 - o / b) * 1000) / 10 }]
        })
      ),
      regressions: Object.entries(parity)
        .filter(([, v]) => !v.match)
        .map(([k]) => k),
    }

    const out = path.join(__dirname, "artifacts/feed_trade_reel_fair_ab_report.json")
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
