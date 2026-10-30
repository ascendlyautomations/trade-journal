#!/usr/bin/env node
/**
 * Isolated feed cand benchmark (embedded Postgres). Not production / not staging cloud.
 * Usage: node supabase/staging/benchmark/run-feed-cand-benchmark.mjs
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import EmbeddedPostgres from "embedded-postgres"
import pg from "pg"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "../../..")
const { Client } = pg

const VIEWERS = [
  { label: "follows_15", id: "aaaaaaaa-aaaa-4aaa-8aaa-000000000015" },
  { label: "follows_40", id: "aaaaaaaa-aaaa-4aaa-8aaa-000000000040" },
  { label: "follows_100", id: "aaaaaaaa-aaaa-4aaa-8aaa-000000000100" },
  { label: "follows_500", id: "aaaaaaaa-aaaa-4aaa-8aaa-000000000500" },
]

const BRANCHES = {
  posts: {
    table: "posts",
    baseline: (lim) => `
      select p.id, p.user_id, p.created_at
      from public.posts p, _feed_cand_ctx c
      where c.v_include_trades
        and p.user_id is distinct from c.v_uid
        and not (p.user_id = any (c.v_block_peers))
        and public._v1_feed_before_cursor(
          p.created_at, 'post', p.id,
          c.v_cursor_ts, c.v_cursor_kind, c.v_cursor_id, c.v_cursor_kind_rank, c.v_cursor_legacy
        )
        and p.user_id = any (c.v_following)
      order by p.created_at desc, p.id desc
      limit ${lim}`,
    proposed: (lim) => `
      select x.id, x.user_id, x.created_at
      from _feed_cand_ctx c
      cross join unnest(c.v_following) as fid
      cross join lateral (
        select p.id, p.user_id, p.created_at
        from public.posts p
        where c.v_include_trades
          and p.user_id = fid
          and p.user_id is distinct from c.v_uid
          and not (p.user_id = any (c.v_block_peers))
          and public._v1_feed_before_cursor(
            p.created_at, 'post', p.id,
            c.v_cursor_ts, c.v_cursor_kind, c.v_cursor_id, c.v_cursor_kind_rank, c.v_cursor_legacy
          )
        order by p.created_at desc, p.id desc
        limit ${lim}
      ) x
      order by x.created_at desc, x.id desc
      limit ${lim}`,
  },
  profile_posts: {
    table: "profile_posts",
    baseline: (lim) => `
      select pp.id, pp.user_id, pp.created_at
      from public.profile_posts pp, _feed_cand_ctx c
      where c.v_include_posts
        and pp.user_id is distinct from c.v_uid
        and not (pp.user_id = any (c.v_block_peers))
        and public._v1_feed_before_cursor(
          pp.created_at, 'profile_post', pp.id,
          c.v_cursor_ts, c.v_cursor_kind, c.v_cursor_id, c.v_cursor_kind_rank, c.v_cursor_legacy
        )
        and pp.user_id = any (c.v_following)
      order by pp.created_at desc, pp.id desc
      limit ${lim}`,
    proposed: (lim) => `
      select x.id, x.user_id, x.created_at
      from _feed_cand_ctx c
      cross join unnest(c.v_following) as fid
      cross join lateral (
        select pp.id, pp.user_id, pp.created_at
        from public.profile_posts pp
        where c.v_include_posts
          and pp.user_id = fid
          and pp.user_id is distinct from c.v_uid
          and not (pp.user_id = any (c.v_block_peers))
          and public._v1_feed_before_cursor(
            pp.created_at, 'profile_post', pp.id,
            c.v_cursor_ts, c.v_cursor_kind, c.v_cursor_id, c.v_cursor_kind_rank, c.v_cursor_legacy
          )
        order by pp.created_at desc, pp.id desc
        limit ${lim}
      ) x
      order by x.created_at desc, x.id desc
      limit ${lim}`,
  },
  achievement_posts: {
    table: "achievement_posts",
    baseline: (lim) => `
      select ap.id, ap.user_id, ap.created_at
      from public.achievement_posts ap
      join public.achievements a on a.id = ap.achievement_id
      , _feed_cand_ctx c
      where c.v_include_achievements
        and ap.user_id is distinct from c.v_uid
        and not (ap.user_id = any (c.v_block_peers))
        and coalesce(a.is_public, true) = true
        and public._v1_feed_before_cursor(
          ap.created_at, 'achievement_post', ap.id,
          c.v_cursor_ts, c.v_cursor_kind, c.v_cursor_id, c.v_cursor_kind_rank, c.v_cursor_legacy
        )
        and ap.user_id = any (c.v_following)
      order by ap.created_at desc, ap.id desc
      limit ${lim}`,
    proposed: (lim) => `
      select x.id, x.user_id, x.created_at
      from _feed_cand_ctx c
      cross join unnest(c.v_following) as fid
      cross join lateral (
        select ap.id, ap.user_id, ap.created_at
        from public.achievement_posts ap
        join public.achievements a on a.id = ap.achievement_id
        where c.v_include_achievements
          and ap.user_id = fid
          and ap.user_id is distinct from c.v_uid
          and not (ap.user_id = any (c.v_block_peers))
          and coalesce(a.is_public, true) = true
          and public._v1_feed_before_cursor(
            ap.created_at, 'achievement_post', ap.id,
            c.v_cursor_ts, c.v_cursor_kind, c.v_cursor_id, c.v_cursor_kind_rank, c.v_cursor_legacy
          )
        order by ap.created_at desc, ap.id desc
        limit ${lim}
      ) x
      order by x.created_at desc, x.id desc
      limit ${lim}`,
  },
  reels: {
    table: "reels",
    baseline: (lim) => `
      select r.id, r.user_id, r.created_at
      from public.reels r, _feed_cand_ctx c
      where c.v_include_reels
        and r.user_id is distinct from c.v_uid
        and not (r.user_id = any (c.v_block_peers))
        and public._v1_feed_before_cursor(
          r.created_at, 'reel', r.id,
          c.v_cursor_ts, c.v_cursor_kind, c.v_cursor_id, c.v_cursor_kind_rank, c.v_cursor_legacy
        )
        and r.user_id = any (c.v_following)
        and r.trade_id is null
      order by r.created_at desc, r.id desc
      limit ${lim}`,
    proposed: (lim) => `
      select x.id, x.user_id, x.created_at
      from _feed_cand_ctx c
      cross join unnest(c.v_following) as fid
      cross join lateral (
        select r.id, r.user_id, r.created_at
        from public.reels r
        where c.v_include_reels
          and r.user_id = fid
          and r.user_id is distinct from c.v_uid
          and not (r.user_id = any (c.v_block_peers))
          and public._v1_feed_before_cursor(
            r.created_at, 'reel', r.id,
            c.v_cursor_ts, c.v_cursor_kind, c.v_cursor_id, c.v_cursor_kind_rank, c.v_cursor_legacy
          )
          and r.trade_id is null
        order by r.created_at desc, r.id desc
        limit ${lim}
      ) x
      order by x.created_at desc, x.id desc
      limit ${lim}`,
  },
}

function readSql(rel) {
  return fs.readFileSync(path.join(__dirname, rel), "utf8")
}

function sumPlanNodes(node, acc = { shared_hit: 0, shared_read: 0, rows: 0 }) {
  if (!node) return acc
  if (node["Shared Hit Blocks"] != null) acc.shared_hit += node["Shared Hit Blocks"]
  if (node["Shared Read Blocks"] != null) acc.shared_read += node["Shared Read Blocks"]
  if (node["Actual Rows"] != null) acc.rows += node["Actual Rows"]
  for (const child of node.Plans ?? []) sumPlanNodes(child, acc)
  return acc
}

async function explainAnalyze(client, sql) {
  const { rows } = await client.query(
    `explain (analyze, buffers, format json) ${sql}`
  )
  const plan = rows[0]["QUERY PLAN"][0]
  const totals = sumPlanNodes(plan.Plan)
  return {
    execution_ms: plan["Execution Time"],
    planning_ms: plan["Planning Time"],
    buffers: totals,
    root_node: plan.Plan["Node Type"],
  }
}

async function setupCtx(client, viewerId, cursor = null) {
  await client.query("begin")
  await client.query("set local role authenticated")
  await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [viewerId])
  await client.query(`
    create temp table _feed_cand_ctx on commit drop as
    select
      $1::uuid as v_uid,
      coalesce(
        (select array_agg(f.following_id order by f.following_id)
         from public.followers f where f.follower_id = $1::uuid),
        '{}'::uuid[]
      ) as v_following,
      coalesce((select public.get_active_block_peer_ids()), '{}'::uuid[]) as v_block_peers,
      9 as lim,
      $2::timestamptz as v_cursor_ts,
      $3::text as v_cursor_kind,
      $4::uuid as v_cursor_id,
      null::int as v_cursor_kind_rank,
      false as v_cursor_legacy,
      false as v_guest,
      true as v_include_trades,
      true as v_include_posts,
      true as v_include_achievements,
      true as v_include_reels
  `, [
    viewerId,
    cursor?.ts ?? null,
    cursor?.kind ?? null,
    cursor?.id ?? null,
  ])
}

async function fetchCand(client, mode, branch, lim = 9) {
  const sql = mode === "baseline" ? BRANCHES[branch].baseline(lim) : BRANCHES[branch].proposed(lim)
  const { rows } = await client.query(sql)
  return rows
}

async function diffCand(client, branch) {
  const b = await fetchCand(client, "baseline", branch)
  const p = await fetchCand(client, "proposed", branch)
  const key = (r) => `${r.id}|${r.user_id}|${r.created_at.toISOString()}`
  const bs = new Set(b.map(key))
  const ps = new Set(p.map(key))
  let onlyB = 0
  let onlyP = 0
  for (const k of bs) if (!ps.has(k)) onlyB++
  for (const k of ps) if (!bs.has(k)) onlyP++
  return { only_baseline: onlyB, only_proposed: onlyP, rows_b: b.length, rows_p: p.length }
}

async function runScale(client, scale) {
  await client.query("rollback").catch(() => {})
  await client.query("begin")
  await client.query(`select set_config('bench.scale', $1, true)`, [scale])
  await client.query(readSql("seed/seed_synthetic.sql"))
  await client.query("commit")

  const counts = await client.query(`
    select
      (select count(*)::bigint from public.posts) as posts,
      (select count(*)::bigint from public.profile_posts) as profile_posts,
      (select count(*)::bigint from public.achievement_posts) as achievement_posts,
      (select count(*)::bigint from public.reels) as reels
  `)

  const bench = []
  const equiv = []

  for (const viewer of VIEWERS) {
    for (const branch of Object.keys(BRANCHES)) {
      await setupCtx(client, viewer.id)
      const baseline = await explainAnalyze(client, BRANCHES[branch].baseline(9))
      const proposed = await explainAnalyze(client, BRANCHES[branch].proposed(9))
      const diff = await diffCand(client, branch)
      await client.query("rollback")

      bench.push({
        scale,
        viewer: viewer.label,
        branch,
        baseline_ms: baseline.execution_ms,
        proposed_ms: proposed.execution_ms,
        speedup: baseline.execution_ms / Math.max(proposed.execution_ms, 0.01),
        baseline_buffers: baseline.buffers,
        proposed_buffers: proposed.buffers,
        baseline_root: baseline.root_node,
        proposed_root: proposed.root_node,
      })
      equiv.push({ scale, viewer: viewer.label, branch, ...diff })
    }
  }

  // cursor page parity (viewer_100, posts)
  await setupCtx(client, VIEWERS[2].id)
  const first = await fetchCand(client, "baseline", "posts")
  await client.query("rollback")
  if (first.length > 0) {
    const last = first[first.length - 1]
    await setupCtx(client, VIEWERS[2].id, {
      ts: last.created_at,
      kind: "post",
      id: last.id,
    })
    const cursorDiff = await diffCand(client, "posts")
    await client.query("rollback")
    equiv.push({ scale, viewer: "follows_100", branch: "posts_cursor", ...cursorDiff })
  }

  // RLS / block fixtures
  for (const [viewerId, label, expectAuthor] of [
    ["bbbbbbbb-bbbb-4bbb-8bbb-000000000002", "viewer_block", publicBenchUuid(1)],
    ["bbbbbbbb-bbbb-4bbb-8bbb-000000000001", "viewer_private", publicBenchUuid(9999)],
  ]) {
    await setupCtx(client, viewerId)
    const visible = await fetchCand(client, "baseline", "posts")
    await client.query("rollback")
    const blockedVisible = visible.some((r) => r.user_id === expectAuthor)
    equiv.push({
      scale,
      viewer: label,
      branch: "posts_rls",
      blocked_author_visible: blockedVisible,
    })
  }

  return { scale, counts: counts.rows[0], bench, equiv }
}

function publicBenchUuid(n) {
  return `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`
}

async function main() {
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(root, "supabase/staging/benchmark/.pgdata"),
    port: 55432,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()

  const client = new Client({
    host: "127.0.0.1",
    port: 55432,
    user: "postgres",
    password: "password",
    database: "postgres",
  })
  await client.connect()

  try {
    await client.query(`do $$ begin create role authenticated; exception when duplicate_object then null; end $$`)
    await client.query("grant usage on schema public to authenticated")

    for (const f of ["init/01_schema.sql", "init/02_indexes.sql", "init/03_feed_helpers.sql"]) {
      await client.query(readSql(f))
    }

    const report = { generated_at: new Date().toISOString(), environment: "embedded-postgres-18", runs: [] }
    for (const scale of ["sparse", "large"]) {
      report.runs.push(await runScale(client, scale))
    }

    const outPath = path.join(__dirname, "artifacts/feed_cand_benchmark_report.json")
    fs.mkdirSync(path.dirname(outPath), { recursive: true })
    fs.writeFileSync(outPath, JSON.stringify(report, null, 2))
    console.log("Wrote", outPath)
    printSummary(report)
  } finally {
    await client.end()
    await embedded.stop()
  }
}

function printSummary(report) {
  for (const run of report.runs) {
    console.log(`\n=== scale=${run.scale} posts=${run.counts.posts} ===`)
    const rows = run.bench.filter((r) => r.branch === "posts")
    for (const r of rows) {
      const win = r.proposed_ms < r.baseline_ms ? "PROPOSED" : "BASELINE"
      console.log(
        `${r.viewer} posts: baseline=${r.baseline_ms.toFixed(2)}ms proposed=${r.proposed_ms.toFixed(2)}ms (${win}) speedup=${r.speedup.toFixed(2)}x`
      )
    }
    const bad = run.equiv.filter((e) => (e.only_baseline ?? 0) + (e.only_proposed ?? 0) > 0)
    if (bad.length) console.log("EQUIV DIFFS", bad)
    else console.log("Equivalence: no row diffs in cand branches")
    const rls = run.equiv.filter((e) => e.branch === "posts_rls" && e.blocked_author_visible)
    if (rls.length) console.log("RLS/BLOCK FAIL", rls)
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
