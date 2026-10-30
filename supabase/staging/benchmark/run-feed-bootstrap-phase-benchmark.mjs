#!/usr/bin/env node
/**
 * Phase-level EXPLAIN (ANALYZE, BUFFERS) for rpc_v1_feed_bootstrap (embedded PG).
 * RLS: migration 20261027160000. RPC: explore baseline + 20261027140000 lateral cand.
 */
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import EmbeddedPostgres from "embedded-postgres"
import pg from "pg"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "../../..")
const { Client } = pg

const VIEWER = "aaaaaaaa-aaaa-4aaa-8aaa-000000000040"
const LIM = 8
const LIM_PLUS = LIM + 1

function read(rel) {
  return fs.readFileSync(path.join(__dirname, rel), "utf8")
}

function buildProductionShapedBody() {
  const exploreSql = fs.readFileSync(
    path.join(root, "supabase/migrations/20260915230000_explore_mode_guest_security_hardening.sql"),
    "utf8"
  )
  const start = exploreSql.indexOf("create or replace function public.rpc_v1_feed_bootstrap(")
  const bodyStart = exploreSql.indexOf("as $$\n", start)
  const bodyEnd = exploreSql.indexOf("\n$$;", bodyStart)
  let body = exploreSql.slice(bodyStart + "as $$\n".length, bodyEnd)
  body = body.replace(
    "v_following uuid[] := '{}'::uuid[];",
    "v_following uuid[] := '{}'::uuid[];\n  v_block_peers uuid[] := '{}'::uuid[];"
  )
  body = body.replace(
    `  if v_uid is not null then
    select coalesce(array_agg(f.following_id), '{}'::uuid[])
    into v_following
    from public.followers f
    where f.follower_id = v_uid;
  end if;

  if v_scope = 'following' and cardinality(v_following) = 0 then`,
    `  if v_uid is not null then
    select coalesce(array_agg(f.following_id), '{}'::uuid[])
    into v_following
    from public.followers f
    where f.follower_id = v_uid;
  end if;

  if not v_guest and v_uid is not null then
    select public.get_active_block_peer_ids() into v_block_peers;
  end if;

  if v_scope = 'following' and cardinality(v_following) = 0 then`
  )
  for (const [from, to] of [
    ["and not public.users_have_active_block(v_uid, p.user_id)", "and (v_guest or not (p.user_id = any (v_block_peers)))"],
    ["and not public.users_have_active_block(v_uid, pp.user_id)", "and (v_guest or not (pp.user_id = any (v_block_peers)))"],
    ["and not public.users_have_active_block(v_uid, ap.user_id)", "and (v_guest or not (ap.user_id = any (v_block_peers)))"],
    ["and not public.users_have_active_block(v_uid, r.user_id)", "and (v_guest or not (r.user_id = any (v_block_peers)))"],
    ["or not public.users_have_active_block(v_uid, s.user_id)", "or v_guest or not (s.user_id = any (v_block_peers))"],
  ]) {
    body = body.replaceAll(from, to)
  }
  body = body.replace("left join public.trades t on t.id = p.trade_id", "")
  body = body.replace(
    "public._v1_feed_post_trade_payload(t, tr, v_guest)",
    "public._v1_feed_post_trade_payload(p.trade_id, tr, v_guest)"
  )
  body = body.replace(
    "from public.trades tx\n                where tx.id = p.trade_id\n                  and coalesce(tx.is_public, false) = true",
    "from public.trades_public_read tx\n                where tx.id = p.trade_id"
  )
  return body
}

function sumPlan(node, acc = { shared_hit: 0 }) {
  if (!node) return acc
  if (node["Shared Hit Blocks"] != null) acc.shared_hit += node["Shared Hit Blocks"]
  for (const c of node.Plans ?? []) sumPlan(c, acc)
  return acc
}

async function explainMs(client, sql, params = []) {
  const { rows } = await client.query(`explain (analyze, buffers, format json) ${sql}`, params)
  const plan = rows[0]["QUERY PLAN"][0]
  return {
    execution_ms: plan["Execution Time"],
    planning_ms: plan["Planning Time"],
    shared_hit: sumPlan(plan.Plan).shared_hit,
  }
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
  p_scope text DEFAULT 'following',
  p_content_filter text DEFAULT 'all',
  p_limit integer DEFAULT 8,
  p_cursor text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path TO public
AS $function$
${body}
$function$;`)
  await client.query(
    fs.readFileSync(
      path.join(root, "supabase/migrations/20261027140000_feed_following_cand_per_followee.sql"),
      "utf8"
    )
  )
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
        $2::timestamptz as v_cursor_ts,
        $3::text as v_cursor_kind,
        $4::uuid as v_cursor_id,
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

function formatProdCursor(cursor) {
  if (!cursor) return null
  const ts =
    cursor.ts instanceof Date
      ? cursor.ts.toISOString().slice(0, 23) + "Z"
      : String(cursor.ts).replace(/\.\d{3}Z$/, ".000Z")
  return `${ts}|${cursor.kind}|${cursor.id}`
}

async function runPhaseSuite(client, viewerId, cursor, label) {
  const phases = {}
  const curStr = formatProdCursor(cursor)

  await client.query("begin")
  await client.query("set local role authenticated")
  await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [viewerId])

  phases.preamble = await explainMs(
    client,
    `select
      (select count(*)::int from public.followers f where f.follower_id = $1),
      (select cardinality(public.get_active_block_peer_ids())),
      (select count(*)::int from public._v1_feed_parse_cursor($2) c)`
  , [viewerId, curStr])

  phases.cand_discovery_and_ranking = await explainMs(
    client,
    `select count(*)::int from (${pageCteSql()}) page`,
    [viewerId, cursor?.ts ?? null, cursor?.kind ?? null, cursor?.id ?? null]
  )

  await client.query(
    `create temp table _feed_page on commit drop as ${pageCteSql()}`,
    [viewerId, cursor?.ts ?? null, cursor?.kind ?? null, cursor?.id ?? null]
  )

  phases.authors = await explainMs(
    client,
    `select count(*)::int from public.profiles p where p.id in (select distinct author_id from _feed_page)`
  )

  phases.item_row_fetches = await explainMs(
    client,
    `select count(*)::int from _feed_page pg
     left join public.posts p on pg.kind = 'post' and p.id = pg.id
     left join public.profile_posts pp on pg.kind = 'profile_post' and pp.id = pg.id
     left join public.achievement_posts ap on pg.kind = 'achievement_post' and ap.id = pg.id
     left join public.achievements a on a.id = ap.achievement_id
     left join public.reels rl on pg.kind = 'reel' and rl.id = pg.id
     left join public.trades rt on rt.id = rl.trade_id`
  )

  phases.trade_payload_stub = await explainMs(
    client,
    `select count(*)::int from _feed_page pg
     join public.posts p on pg.kind = 'post' and p.id = pg.id
     cross join lateral (select public._v1_feed_post_trade_payload(p.trade_id, null::public.reels, false) j) x`
  )

  phases.engagement = await explainMs(
    client,
    `select count(*)::int from _feed_page pg
     cross join lateral public.feed_engagement_counts(
       (select coalesce(array_agg(id) filter (where kind = 'post'), '{}') from _feed_page),
       (select coalesce(array_agg(id) filter (where kind = 'profile_post'), '{}') from _feed_page),
       (select coalesce(array_agg(id) filter (where kind = 'achievement_post'), '{}') from _feed_page),
       (select coalesce(array_agg(id) filter (where kind = 'reel'), '{}') from _feed_page)
     ) e`
  )

  phases.stories = await explainMs(
    client,
    `select count(*)::int from public.stories s
     where s.user_id = any (
       array_append(
         (select coalesce(array_agg(f.following_id), '{}') from public.followers f where f.follower_id = $1),
         $1::uuid
       )
     )
     and s.created_at > timezone('utc', now()) - interval '24 hours'`,
    [viewerId]
  )

  phases.story_authors = await explainMs(
    client,
    `select count(*)::int from public.profiles p
     where p.id in (
       select distinct s.user_id from public.stories s
       where s.created_at > timezone('utc', now()) - interval '24 hours'
         and s.user_id = any (
           array_append(
             (select coalesce(array_agg(f.following_id), '{}') from public.followers f where f.follower_id = $1),
             $1::uuid
           )
         )
     )`,
    [viewerId]
  )

  phases.full_rpc = await explainMs(
    client,
    `select public.rpc_v1_feed_bootstrap('following', 'all', $1, $2)`,
    [LIM, curStr]
  )

  phases.following_ids_echo = await explainMs(
    client,
    `select jsonb_array_length(to_jsonb(coalesce(
      (select array_agg(f.following_id) from public.followers f where f.follower_id = $1),
      '{}'::uuid[]
    )))`,
    [viewerId]
  )

  await client.query("rollback")
  return { label, phases }
}

async function main() {
  const scale = process.env.FEED_PHASE_SCALE || "large"
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-phase-bench"),
    port: 55448,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()

  const client = new Client({
    host: "127.0.0.1",
    port: 55448,
    user: "postgres",
    password: "password",
    database: "postgres",
  })
  await client.connect()

  try {
    await client.query(
      `do $$ begin create role authenticated; exception when duplicate_object then null; end $$`
    )
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
    await installRpc(client)

    await client.query("begin")
    await client.query(`select set_config('bench.scale', $1, true)`, [scale])
    await client.query(read("seed/seed_synthetic.sql"))
    await client.query("commit")

    const counts = (
      await client.query(`
      select
        (select count(*)::bigint from public.posts) posts,
        (select count(*)::bigint from public.profile_posts) profile_posts,
        (select count(*)::bigint from public.stories) stories
    `)
    ).rows[0]

    const first = await runPhaseSuite(client, VIEWER, null, "first_page")
    let cursor = null
    await client.query("begin")
    await client.query("set local role authenticated")
    await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [VIEWER])
    const { rows: pageRows } = await client.query(pageCteSql(), [VIEWER, null, null, null])
    await client.query("rollback")
    if (pageRows.length) {
      const last = pageRows[pageRows.length - 1]
      cursor = { ts: last.created_at, kind: last.kind, id: last.id }
    }
    const cursorPage = await runPhaseSuite(client, VIEWER, cursor, "cursor_page")

    const report = {
      generated_at: new Date().toISOString(),
      source: "embedded-postgres-18",
      rls: "20261027160000",
      rpc_cand: "20261027140000",
      scale,
      viewer: VIEWER,
      table_counts: counts,
      note_trade_payload: "init/04 stub returns null; prod DEFINER payload not modeled",
      note_engagement: "feed_engagement_counts stub returns 0 rows (empty like/comment tables)",
      runs: [first, cursorPage],
    }

    const out = path.join(__dirname, "artifacts/feed_bootstrap_phase_report.json")
    fs.mkdirSync(path.dirname(out), { recursive: true })
    fs.writeFileSync(out, JSON.stringify(report, null, 2))
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
