#!/usr/bin/env node
/**
 * EXPLAIN (ANALYZE) for production-shaped `items` CTE + tail JSON (embedded PG).
 * Uses real _v1_feed_post_trade_payload from migration when loadable.
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

function read(rel) {
  return fs.readFileSync(path.join(__dirname, rel), "utf8")
}

function sumPlan(node, acc = { shared_hit: 0, index_loops: 0, filter_removed: 0 }) {
  if (!node) return acc
  if (node["Shared Hit Blocks"] != null) acc.shared_hit += node["Shared Hit Blocks"]
  if (node["Node Type"] === "Index Scan" || node["Node Type"] === "Index Only Scan") {
    acc.index_loops += node["Actual Loops"] ?? 1
  }
  if (node["Rows Removed by Filter"] != null) acc.filter_removed += node["Rows Removed by Filter"]
  for (const c of node.Plans ?? []) sumPlan(c, acc)
  return acc
}

async function explainMs(client, sql, params = []) {
  const { rows } = await client.query(`explain (analyze, buffers, format json) ${sql}`, params)
  const plan = rows[0]["QUERY PLAN"][0]
  return { execution_ms: plan["Execution Time"], ...sumPlan(plan.Plan) }
}

async function installTradePayloadStub(client) {
  await client.query(`
    create or replace function public._v1_feed_post_trade_payload(
      p_trade_id uuid, p_reel public.reels, p_guest boolean
    ) returns jsonb language plpgsql stable security definer set search_path = public as $$
    declare v_trade public.trades%rowtype;
    begin
      if p_trade_id is null then return null; end if;
      select * into v_trade from public.trades t where t.id = p_trade_id;
      if v_trade.id is null then return null; end if;
      return jsonb_build_object(
        'ticker', v_trade.ticker, 'direction', v_trade.direction,
        'pnl', v_trade.pnl, 'rr', v_trade.rr, 'is_public', v_trade.is_public,
        'public_description', v_trade.public_description,
        'entry_time', v_trade.created_at, 'mode', v_trade.mode
      );
    end;
    $$;
    grant execute on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) to authenticated;
  `)
}

/** Production `items` + `authors` CTEs (v_guest=false), parameterized page temp table. */
function itemsAuthorsSql(vGuest = false) {
  const vg = vGuest ? "true" : "false"
  return `
    with authors as (
      select coalesce(
        jsonb_object_agg(
          p.id::text,
          jsonb_build_object(
            'id', p.id,
            'username', p.username,
            'display_name', p.username,
            'avatar_url', p.avatar_url
          )
        ),
        '{}'::jsonb
      ) as map
      from public.profiles p
      where p.id in (select distinct author_id from _feed_page)
    ),
    items as (
      select coalesce(jsonb_agg(item order by rn), '[]'::jsonb) as arr
      from (
        select
          pg.rn,
          case pg.kind
            when 'post' then jsonb_build_object(
              'kind', 'post',
              'id', p.id,
              'created_at', to_char(timezone('utc', p.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
              'author_id', p.user_id,
              'payload', jsonb_build_object(
                'id', p.id,
                'user_id', p.user_id,
                'trade_id', p.trade_id,
                'created_at', p.created_at,
                'pnl', p.pnl,
                'rr', p.rr,
                'image_url', p.image_url,
                'image_crop', p.image_crop,
                'profiles', jsonb_build_object(
                  'username', au.map -> p.user_id::text ->> 'username',
                  'avatar_url', au.map -> p.user_id::text ->> 'avatar_url'
                ),
                'trades', public._v1_feed_post_trade_payload(p.trade_id, tr, ${vg})
              )
            )
            when 'profile_post' then jsonb_build_object(
              'kind', 'profile_post',
              'id', pp.id,
              'created_at', to_char(timezone('utc', pp.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
              'author_id', pp.user_id,
              'payload', jsonb_build_object(
                'id', pp.id,
                'user_id', pp.user_id,
                'content', pp.content,
                'image_url', pp.image_url,
                'image_crop', pp.image_crop,
                'created_at', pp.created_at,
                'room_id', pp.room_id,
                'room_name', pp.room_name,
                'room_logo', pp.room_logo,
                'room_description', pp.room_description,
                'profiles', jsonb_build_object(
                  'username', au.map -> pp.user_id::text ->> 'username',
                  'avatar_url', au.map -> pp.user_id::text ->> 'avatar_url'
                )
              )
            )
            when 'achievement_post' then jsonb_build_object(
              'kind', 'achievement_post',
              'id', ap.id,
              'created_at', to_char(timezone('utc', ap.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
              'author_id', ap.user_id,
              'payload', jsonb_build_object(
                'id', ap.id,
                'user_id', ap.user_id,
                'achievement_id', ap.achievement_id,
                'created_at', ap.created_at,
                'metadata', ap.metadata,
                'achievements', case when a.id is null then null else to_jsonb(a) end,
                'profiles', jsonb_build_object(
                  'username', au.map -> ap.user_id::text ->> 'username',
                  'avatar_url', au.map -> ap.user_id::text ->> 'avatar_url'
                )
              )
            )
            when 'reel' then jsonb_build_object(
              'kind', 'reel',
              'id', rl.id,
              'created_at', to_char(timezone('utc', rl.created_at), 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
              'author_id', rl.user_id,
              'payload', jsonb_build_object(
                'id', rl.id,
                'user_id', rl.user_id,
                'caption', rl.caption,
                'video_url', rl.video_url,
                'thumbnail_url', rl.thumbnail_url,
                'duration_seconds', rl.duration_seconds,
                'visibility', rl.visibility,
                'trade_id', rl.trade_id,
                'kind', rl.kind,
                'created_at', rl.created_at,
                'profiles', jsonb_build_object(
                  'username', au.map -> rl.user_id::text ->> 'username',
                  'avatar_url', au.map -> rl.user_id::text ->> 'avatar_url'
                ),
                'trades', case when rt.id is null then null else jsonb_build_object(
                  'id', rt.id,
                  'public_description', rt.public_description,
                  'is_public', rt.is_public,
                  'ticker', rt.ticker,
                  'direction', rt.direction,
                  'pnl', rt.pnl,
                  'rr', rt.rr
                ) end
              )
            )
          end as item
        from _feed_page pg
        cross join authors au
        left join public.posts p on pg.kind = 'post' and p.id = pg.id
        left join lateral (
          select r.*
          from public.reels r
          where r.trade_id = coalesce(p.trade_id, p.id)
          order by r.created_at desc
          limit 1
        ) tr on pg.kind = 'post'
        left join public.profile_posts pp on pg.kind = 'profile_post' and pp.id = pg.id
        left join public.achievement_posts ap on pg.kind = 'achievement_post' and ap.id = pg.id
        left join public.achievements a on a.id = ap.achievement_id
        left join public.reels rl on pg.kind = 'reel' and rl.id = pg.id
        left join public.trades rt on rt.id = rl.trade_id
      ) built
      where item is not null
    )
    select (select map from authors) as authors_map, (select arr from items) as items_arr
  `
}

async function main() {
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-items-explain"),
    port: 55449,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()
  const client = new Client({
    host: "127.0.0.1",
    port: 55449,
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
    await installTradePayloadStub(client)

    const body = buildProductionShapedBody()
    await client.query(`
CREATE OR REPLACE FUNCTION public.rpc_v1_feed_bootstrap(p_scope text, p_content_filter text, p_limit integer, p_cursor text)
RETURNS jsonb LANGUAGE plpgsql STABLE SET search_path TO public AS $function$ ${body} $function$;`)
    await client.query(
      fs.readFileSync(
        path.join(root, "supabase/migrations/20261027140000_feed_following_cand_per_followee.sql"),
        "utf8"
      )
    )

    await client.query("begin")
    await client.query(`select set_config('bench.scale', 'large', true)`)
    await client.query(read("seed/seed_synthetic.sql"))
    await client.query("commit")

    await client.query("begin")
    await client.query("set local role authenticated")
    await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [VIEWER])
    const { rows: rpcRows } = await client.query(
      `select public.rpc_v1_feed_bootstrap('following','all',$1,null) as j`,
      [LIM]
    )
    const items = rpcRows[0].j.data.items
    await client.query(
      `create temp table _feed_page (rn int, kind text, id uuid, author_id uuid, created_at timestamptz)`
    )
    for (let i = 0; i < items.length; i++) {
      const it = items[i]
      await client.query(
        `insert into _feed_page values ($1,$2,$3,$4,$5)`,
        [i + 1, it.kind, it.id, it.author_id, it.created_at]
      )
    }

    const report = {
      source: "embedded-postgres-18",
      scale: "large",
      page_rows: items.length,
      trade_payload: "embedded-definer-stub (select trades row + jsonb_build_object)",
      measures: {},
    }

    report.measures.authors_only = await explainMs(
      client,
      `select count(*) from public.profiles p where p.id in (select distinct author_id from _feed_page)`
    )
    report.measures.items_authors_hydration = await explainMs(client, itemsAuthorsSql())
    report.measures.trade_payload_per_post = await explainMs(
      client,
      `select count(*) from _feed_page pg
       join public.posts p on pg.kind='post' and p.id=pg.id
       cross join lateral (select public._v1_feed_post_trade_payload(p.trade_id, null::public.reels, false)) x`
    )
    report.measures.post_reel_lateral = await explainMs(
      client,
      `select count(*) from _feed_page pg
       join public.posts p on pg.kind='post' and p.id=pg.id
       left join lateral (
         select r.* from public.reels r
         where r.trade_id = coalesce(p.trade_id, p.id)
         order by r.created_at desc limit 1
       ) tr on true`
    )
    report.measures.full_rpc_same_session = await explainMs(
      client,
      `select public.rpc_v1_feed_bootstrap('following','all',$1,null)`,
      [LIM]
    )

    const postKinds = items.filter((x) => x.kind === "post").length
    report.post_rows_on_page = postKinds

    await client.query("rollback")

    const out = path.join(__dirname, "artifacts/feed_items_hydration_report.json")
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
