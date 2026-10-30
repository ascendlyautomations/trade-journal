#!/usr/bin/env node
/**
 * EXPLAIN (ANALYZE, BUFFERS) for production-shaped Following feed cand (per-followee LATERAL).
 * Embedded Postgres only — not production / not staging cloud.
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import EmbeddedPostgres from "embedded-postgres"
import pg from "pg"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "../../..")
const { Client } = pg

const VIEWER_40 = "aaaaaaaa-aaaa-4aaa-8aaa-000000000040"
const LIM = 9

/** Production cand branch shape (20261027140000), following scope only. */
const PRODUCTION_BRANCHES = {
  posts: (lim) => `
    select 'post'::text as kind, x.id, x.user_id as author_id, x.created_at
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
  profile_posts: (lim) => `
    select 'profile_post'::text as kind, x.id, x.user_id as author_id, x.created_at
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
  achievement_posts: (lim) => `
    select 'achievement_post'::text as kind, x.id, x.user_id as author_id, x.created_at
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
  reels: (lim) => `
    select 'reel'::text as kind, x.id, x.user_id as author_id, x.created_at
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
}

function readSql(rel) {
  return fs.readFileSync(path.join(__dirname, rel), "utf8")
}

function walkPlan(node, acc) {
  if (!node) return acc
  acc.nodes++
  if (node["Node Type"] === "Nested Loop") acc.nested_loops++
  if (node["Node Type"] === "Index Scan" || node["Node Type"] === "Index Only Scan") {
    acc.index_scans++
    acc.index_loops += node["Actual Loops"] ?? 1
    acc.index_rows += node["Actual Rows"] ?? 0
  }
  if (node["Rows Removed by Filter"] != null) {
    acc.rows_removed_filter += node["Rows Removed by Filter"]
  }
  if (node["Filter"] && String(node["Filter"]).includes("viewer_has_block_with")) {
    acc.block_filter_nodes++
  }
  if (node["Shared Hit Blocks"] != null) acc.shared_hit += node["Shared Hit Blocks"]
  if (node["Shared Read Blocks"] != null) acc.shared_read += node["Shared Read Blocks"]
  for (const child of node.Plans ?? []) walkPlan(child, acc)
  return acc
}

async function explainAnalyze(client, sql) {
  const { rows } = await client.query(`explain (analyze, buffers, format json) ${sql}`)
  const plan = rows[0]["QUERY PLAN"][0]
  const stats = walkPlan(plan.Plan, {
    nodes: 0,
    nested_loops: 0,
    index_scans: 0,
    index_loops: 0,
    index_rows: 0,
    rows_removed_filter: 0,
    block_filter_nodes: 0,
    shared_hit: 0,
    shared_read: 0,
  })
  return {
    execution_ms: plan["Execution Time"],
    planning_ms: plan["Planning Time"],
    root: plan.Plan["Node Type"],
    stats,
    plan_json: plan.Plan,
  }
}

async function setupCtx(client, viewerId, cursor) {
  await client.query("begin")
  await client.query("set local role authenticated")
  await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [viewerId])
  await client.query(
    `
    create temp table _feed_cand_ctx on commit drop as
    select
      $1::uuid as v_uid,
      coalesce(
        (select array_agg(f.following_id order by f.following_id)
         from public.followers f where f.follower_id = $1::uuid),
        '{}'::uuid[]
      ) as v_following,
      coalesce((select public.get_active_block_peer_ids()), '{}'::uuid[]) as v_block_peers,
      $5::int as lim,
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
  `,
    [viewerId, cursor?.ts ?? null, cursor?.kind ?? null, cursor?.id ?? null, LIM]
  )
  const { rows } = await client.query(`select cardinality(v_following) as n from _feed_cand_ctx`)
  return rows[0].n
}

async function main() {
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-following-explain"),
    port: 55447,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()

  const client = new Client({
    host: "127.0.0.1",
    port: 55447,
    user: "postgres",
    password: "password",
    database: "postgres",
  })
  await client.connect()

  try {
    await client.query(
      `do $$ begin create role authenticated; exception when duplicate_object then null; end $$`
    )
    await client.query("grant usage on schema public to authenticated")
    for (const f of ["init/01_schema.sql", "init/02_indexes.sql", "init/03_feed_helpers.sql"]) {
      await client.query(readSql(f))
    }
    const scale = process.env.FEED_CAND_EXPLAIN_SCALE || "large"
    await client.query("begin")
    await client.query(`select set_config('bench.scale', $1, true)`, [scale])
    await client.query(readSql("seed/seed_synthetic.sql"))
    await client.query("commit")

    const counts = (
      await client.query(`
      select
        (select count(*)::bigint from public.posts) as posts,
        (select count(*)::bigint from public.profile_posts) as profile_posts,
        (select count(*)::bigint from public.achievement_posts) as achievement_posts,
        (select count(*)::bigint from public.reels) as reels
    `)
    ).rows[0]

    const report = {
      generated_at: new Date().toISOString(),
      environment: "embedded-postgres-18",
      scale,
      viewer: "follows_40",
      table_counts: counts,
      branches: {},
    }

    let cursor = null
    for (const phase of ["first_page", "cursor_page"]) {
      const followN = await setupCtx(client, VIEWER_40, cursor)
      report[`${phase}_follow_count`] = followN

      for (const branch of Object.keys(PRODUCTION_BRANCHES)) {
        const sql = PRODUCTION_BRANCHES[branch](LIM)
        const ex = await explainAnalyze(client, sql)
        report.branches[`${branch}_${phase}`] = {
          execution_ms: ex.execution_ms,
          planning_ms: ex.planning_ms,
          root_node: ex.root,
          ...ex.stats,
        }
      }

      if (phase === "first_page") {
        const { rows } = await client.query(PRODUCTION_BRANCHES.posts(LIM))
        if (rows.length > 0) {
          const last = rows[rows.length - 1]
          cursor = { ts: last.created_at, kind: "post", id: last.id }
          report.cursor_sample = {
            created_at: last.created_at,
            id: last.id,
          }
        }
      }
      await client.query("rollback")
    }

    // Full cand union (four branches, production merge — no ranked window)
    for (const phase of ["first_page", "cursor_page"]) {
      const followN = await setupCtx(client, VIEWER_40, phase === "cursor_page" ? cursor : null)
      const unionSql = Object.values(PRODUCTION_BRANCHES)
        .map((fn) => `(${fn(LIM)})`)
        .join(" union all ")
      const ex = await explainAnalyze(client, unionSql)
      report[`merged_cand_${phase}`] = {
        follow_count: followN,
        execution_ms: ex.execution_ms,
        ...ex.stats,
      }
      await client.query("rollback")
    }

    const outPath = path.join(__dirname, "artifacts/feed_cand_following_explain_report.json")
    fs.mkdirSync(path.dirname(outPath), { recursive: true })
    fs.writeFileSync(outPath, JSON.stringify(report, null, 2))
    console.log(JSON.stringify(report, null, 2))
  } finally {
    await client.end()
    await embedded.stop()
  }
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
