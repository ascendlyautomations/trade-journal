#!/usr/bin/env node
/**
 * Isolated benchmark: baseline _v1_feed_post_trade_payload (viewer_has_block_with)
 * vs optimized overload with precomputed v_block_peers.
 * Measures cand vs items hydration; no production access.
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
const VIEWER_BLOCK = "bbbbbbbb-bbbb-4bbb-8bbb-000000000002"
const LIM = 8
const LIM_PLUS = LIM + 1
const WARMUP = 2
const ITERS = 8

function read(rel) {
  return fs.readFileSync(path.join(__dirname, rel), "utf8")
}

function median(nums) {
  const s = [...nums].sort((a, b) => a - b)
  const m = Math.floor(s.length / 2)
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2
}

function sumPlan(node, acc = { viewer_has_block: 0, get_block_peers: 0 }) {
  if (!node) return acc
  const f = String(node.Filter ?? "")
  const ci = String(node["Index Cond"] ?? "")
  const txt = `${f} ${ci} ${node["Function Name"] ?? ""}`
  if (txt.includes("viewer_has_block_with")) acc.viewer_has_block += node["Actual Loops"] ?? 1
  if (txt.includes("get_active_block_peer_ids")) acc.get_block_peers += node["Actual Loops"] ?? 1
  for (const c of node.Plans ?? []) sumPlan(c, acc)
  return acc
}

async function explainMs(client, sql, params = []) {
  const { rows } = await client.query(`explain (analyze, buffers, format json) ${sql}`, params)
  const plan = rows[0]["QUERY PLAN"][0]
  return {
    execution_ms: plan["Execution Time"],
    planning_ms: plan["Planning Time"],
    plan_signals: sumPlan(plan.Plan),
  }
}

async function timedRuns(client, label, fn) {
  for (let i = 0; i < WARMUP; i++) await fn()
  const samples = []
  for (let i = 0; i < ITERS; i++) samples.push(await fn())
  return {
    label,
    median_ms: Math.round(median(samples.map((s) => s.execution_ms)) * 100) / 100,
    samples_ms: samples.map((s) => Math.round(s.execution_ms * 100) / 100),
    plan_signals: samples[samples.length - 1].plan_signals,
  }
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

function itemsHydrationSql(tradePayloadExpr) {
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
                'trades', ${tradePayloadExpr}
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
                'created_at', pp.created_at,
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
                'trade_id', rl.trade_id,
                'profiles', jsonb_build_object(
                  'username', au.map -> rl.user_id::text ->> 'username',
                  'avatar_url', au.map -> rl.user_id::text ->> 'avatar_url'
                )
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
      ) built
      where item is not null
    )
    select octet_length((select arr from items)::text)::bigint as payload_bytes
  `
}

async function installPayloadVariants(client) {
  const payloadBody = `
    declare
      v_trade public.trades%rowtype;
    begin
      if p_trade_id is null then
        return null;
      end if;

      select * into v_trade from public.trades t where t.id = p_trade_id;
      if v_trade.id is null then
        return null;
      end if;

      {{BLOCK_GATE}}

      if not public.profile_is_visible_to_viewer(v_trade.user_id) then
        return null;
      end if;

      if coalesce(p_guest, false) then
        if coalesce(v_trade.is_public, false) = false then
          return null;
        end if;
        if not exists (
          select 1 from public.profiles pr
          where pr.id = v_trade.user_id and coalesce(pr.is_private, false) = false
        ) then
          return null;
        end if;
      elsif auth.uid() is distinct from v_trade.user_id
         and not (
           coalesce(v_trade.is_public, false)
           and public.profile_viewer_can_view_trades(v_trade.user_id)
         )
      then
        return null;
      end if;

      return jsonb_build_object(
        'created_at', v_trade.created_at,
        'user_id', v_trade.user_id,
        'is_public', v_trade.is_public,
        'participating_account_modes', public.copy_trade_public_participating_account_modes_json(v_trade),
        'reels', case when p_reel.id is null then null else jsonb_build_object(
          'id', p_reel.id, 'video_url', p_reel.video_url, 'trade_id', p_reel.trade_id
        ) end
      );
    end;
  `

  const baselineBlock = `
      if public.viewer_has_block_with(v_trade.user_id) then
        return null;
      end if;`

  const optimizedBlock = `
      if v_trade.user_id = any (p_block_peers) then
        return null;
      end if;`

  await client.query(`
    alter table public.trades add column if not exists public_description text;
    alter table public.profiles add column if not exists is_hidden_from_community boolean not null default false;

    create or replace function public.copy_trade_public_participating_account_modes_json(p_trade public.trades)
    returns jsonb language sql stable as $$ select '[]'::jsonb $$;

    create or replace function public.profile_is_visible_to_viewer(p_profile_id uuid)
    returns boolean language sql stable security definer set search_path = public as $$
      select p_profile_id is not null
        and exists (
          select 1 from public.profiles p
          where p.id = p_profile_id
            and (p.id = auth.uid() or coalesce(p.is_hidden_from_community, false) = false)
        );
    $$;

    create or replace function public.profile_viewer_can_view_trades(p_profile_id uuid)
    returns boolean language sql stable security definer set search_path = public as $$
      select p_profile_id is not null
        and (
          p_profile_id = auth.uid()
          or exists (
            select 1 from public.profiles p
            where p.id = p_profile_id and coalesce(p.is_private, false) = false
          )
          or exists (
            select 1 from public.followers f
            where f.follower_id = auth.uid() and f.following_id = p_profile_id
          )
        );
    $$;

    grant execute on function public.profile_is_visible_to_viewer(uuid) to anon, authenticated;
    grant execute on function public.profile_viewer_can_view_trades(uuid) to authenticated;

    create or replace function public._v1_feed_post_trade_payload(
      p_trade_id uuid, p_reel public.reels, p_guest boolean
    )
    returns jsonb language plpgsql stable security definer set search_path = public, pg_temp
    as $$ ${payloadBody.replace("{{BLOCK_GATE}}", baselineBlock)} $$;

    create or replace function public._v1_feed_post_trade_payload(
      p_trade_id uuid, p_reel public.reels, p_guest boolean, p_block_peers uuid[]
    )
    returns jsonb language plpgsql stable security definer set search_path = public, pg_temp
    as $$ ${payloadBody.replace("{{BLOCK_GATE}}", optimizedBlock)} $$;

    grant execute on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean) to authenticated;
    grant execute on function public._v1_feed_post_trade_payload(uuid, public.reels, boolean, uuid[]) to authenticated;
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

async function main() {
  const scale = process.env.FEED_PHASE_SCALE || "large"
  const embedded = new EmbeddedPostgres({
    databaseDir: path.join(__dirname, ".pgdata-trade-payload-bench"),
    port: 55450,
    persistent: false,
  })
  await embedded.initialise()
  await embedded.start()

  const client = new Client({
    host: "127.0.0.1",
    port: 55450,
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
    await client.query(`select set_config('bench.scale', $1, true)`, [scale])
    await client.query(read("seed/seed_synthetic.sql"))
    await client.query("commit")

    const counts = (
      await client.query(`
        select
          (select count(*)::int from public.posts) posts,
          (select count(*)::int from public.followers f where f.follower_id = $1) following_n
      `, [VIEWER])
    ).rows[0]

    await client.query("begin")
    await client.query("set local role authenticated")
    await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [VIEWER])

    await client.query(
      `create temp table _feed_page (rn int, kind text, id uuid, author_id uuid, created_at timestamptz) on commit drop`
    )
    const { rows: pageRows } = await client.query(
      `with page as (${pageCteSql()})
       insert into _feed_page (rn, kind, id, author_id, created_at)
       select row_number() over ()::int, kind, id, author_id, created_at from page
       returning *`,
      [VIEWER]
    )
    const postRows = pageRows.filter((r) => r.kind === "post").length

    const blockPeers = (
      await client.query(`select public.get_active_block_peer_ids() as peers`)
    ).rows[0].peers

    const equiv = await client.query(
      `select count(*)::int as mismatches
       from _feed_page pg
       join public.posts p on pg.kind = 'post' and p.id = pg.id
       left join lateral (
         select r.* from public.reels r
         where r.trade_id = coalesce(p.trade_id, p.id)
         order by r.created_at desc limit 1
       ) tr on true
       cross join lateral (select public._v1_feed_post_trade_payload(p.trade_id, tr, false) as b) x
       cross join lateral (
         select public._v1_feed_post_trade_payload(p.trade_id, tr, false, $1::uuid[]) as o
       ) y
       where x.b is distinct from y.o`,
      [blockPeers]
    )

    async function loadTradeHeavyPage(viewerId) {
      await client.query(`delete from _feed_page`)
      await client.query(
        `insert into _feed_page (rn, kind, id, author_id, created_at)
         select row_number() over ()::int, 'post', p.id, p.user_id, p.created_at
         from public.posts p
         where p.user_id in (
           select f.following_id from public.followers f where f.follower_id = $1
         )
         order by p.created_at desc, p.id desc
         limit ${LIM}`,
        [viewerId]
      )
    }

    const candDiscovery = await timedRuns(client, "cand_discovery_and_ranking", () =>
      explainMs(client, `select count(*)::int from (${pageCteSql()}) page`, [VIEWER])
    )

    const itemsBaseline = await timedRuns(client, "items_hydration_mixed_page_baseline", () =>
      explainMs(
        client,
        itemsHydrationSql("public._v1_feed_post_trade_payload(p.trade_id, tr, false)")
      )
    )

    const itemsOptimized = await timedRuns(client, "items_hydration_mixed_page_optimized", () =>
      explainMs(
        client,
        itemsHydrationSql(
          "public._v1_feed_post_trade_payload(p.trade_id, tr, false, (select public.get_active_block_peer_ids()))"
        )
      )
    )

    await loadTradeHeavyPage(VIEWER)
    const tradeHeavyCount = (await client.query(`select count(*)::int as n from _feed_page`)).rows[0].n

    const equivTradeHeavy = await client.query(
      `select count(*)::int as mismatches
       from _feed_page pg
       join public.posts p on pg.kind = 'post' and p.id = pg.id
       left join lateral (
         select r.* from public.reels r
         where r.trade_id = coalesce(p.trade_id, p.id)
         order by r.created_at desc limit 1
       ) tr on true
       cross join lateral (select public._v1_feed_post_trade_payload(p.trade_id, tr, false) as b) x
       cross join lateral (
         select public._v1_feed_post_trade_payload(p.trade_id, tr, false, $1::uuid[]) as o
       ) y
       where x.b is distinct from y.o`,
      [blockPeers]
    )

    const blockCheckOnly = await timedRuns(client, "viewer_has_block_with_per_post", () =>
      explainMs(
        client,
        `select count(*)::int from _feed_page pg
         join public.posts p on pg.kind = 'post' and p.id = pg.id
         cross join lateral (select public.viewer_has_block_with(p.user_id) as blocked) x`
      )
    )

    const blockPeersOnly = await timedRuns(client, "block_peers_array_per_post", () =>
      explainMs(
        client,
        `select count(*)::int from _feed_page pg
         join public.posts p on pg.kind = 'post' and p.id = pg.id
         cross join lateral (select (p.user_id = any ($1::uuid[])) as blocked) x`,
        [blockPeers]
      )
    )

    const itemsTradeHeavyBaseline = await timedRuns(client, "items_hydration_trade_heavy_baseline", () =>
      explainMs(
        client,
        itemsHydrationSql("public._v1_feed_post_trade_payload(p.trade_id, tr, false)")
      )
    )

    const itemsTradeHeavyOptimized = await timedRuns(client, "items_hydration_trade_heavy_optimized", () =>
      explainMs(
        client,
        itemsHydrationSql(
          "public._v1_feed_post_trade_payload(p.trade_id, tr, false, (select public.get_active_block_peer_ids()))"
        )
      )
    )

    const tradePayloadBaseline = await timedRuns(client, "trade_payload_baseline", () =>
      explainMs(
        client,
        `select coalesce(sum(octet_length(j::text)), 0)::bigint from _feed_page pg
         join public.posts p on pg.kind = 'post' and p.id = pg.id
         left join lateral (
           select r.* from public.reels r where r.trade_id = coalesce(p.trade_id, p.id)
           order by r.created_at desc limit 1
         ) tr on true
         cross join lateral (
           select public._v1_feed_post_trade_payload(p.trade_id, tr, false) j
         ) x`
      )
    )

    const tradePayloadOptimized = await timedRuns(client, "trade_payload_with_block_peers", () =>
      explainMs(
        client,
        `select coalesce(sum(octet_length(j::text)), 0)::bigint from _feed_page pg
         join public.posts p on pg.kind = 'post' and p.id = pg.id
         left join lateral (
           select r.* from public.reels r where r.trade_id = coalesce(p.trade_id, p.id)
           order by r.created_at desc limit 1
         ) tr on true
         cross join lateral (
           select public._v1_feed_post_trade_payload(p.trade_id, tr, false, $1::uuid[]) j
         ) x`,
        [blockPeers]
      )
    )

    const fullRpc = await timedRuns(client, "full_rpc_baseline", () =>
      explainMs(client, `select public.rpc_v1_feed_bootstrap('following', 'all', $1, null)`, [LIM])
    )

    const fullRpcTradesOnly = await timedRuns(client, "full_rpc_trades_filter", () =>
      explainMs(client, `select public.rpc_v1_feed_bootstrap('following', 'trades', $1, null)`, [LIM])
    )

    await client.query(`select set_config('request.jwt.claim.sub', $1, true)`, [VIEWER_BLOCK])
    await loadTradeHeavyPage(VIEWER_BLOCK)
    const blockPeersBlockedViewer = (
      await client.query(`select public.get_active_block_peer_ids() as peers`)
    ).rows[0].peers

    const tradePayloadBaselineBlocked = await timedRuns(
      client,
      "trade_payload_baseline_viewer_with_block",
      () =>
        explainMs(
          client,
          `select coalesce(sum(octet_length(j::text)), 0)::bigint from _feed_page pg
         join public.posts p on pg.kind = 'post' and p.id = pg.id
         left join lateral (
           select r.* from public.reels r where r.trade_id = coalesce(p.trade_id, p.id)
           order by r.created_at desc limit 1
         ) tr on true
         cross join lateral (
           select public._v1_feed_post_trade_payload(p.trade_id, tr, false) j
         ) x`
        )
    )

    const tradePayloadOptimizedBlocked = await timedRuns(
      client,
      "trade_payload_optimized_viewer_with_block",
      () =>
        explainMs(
          client,
          `select coalesce(sum(octet_length(j::text)), 0)::bigint from _feed_page pg
         join public.posts p on pg.kind = 'post' and p.id = pg.id
         left join lateral (
           select r.* from public.reels r where r.trade_id = coalesce(p.trade_id, p.id)
           order by r.created_at desc limit 1
         ) tr on true
         cross join lateral (
           select public._v1_feed_post_trade_payload(p.trade_id, tr, false, $1::uuid[]) j
         ) x`,
          [blockPeersBlockedViewer]
        )
    )

    await client.query("rollback")

    const report = {
      generated_at: new Date().toISOString(),
      environment: "embedded-postgres-18",
      scale,
      viewer: VIEWER,
      table_counts: counts,
      page_rows: pageRows.length,
      post_rows_on_page: postRows,
      trade_heavy_page_rows: tradeHeavyCount,
      block_peers_count: blockPeers?.length ?? 0,
      payload_equivalence_mismatches_mixed_page: equiv.rows[0].mismatches,
      payload_equivalence_mismatches_trade_heavy: equivTradeHeavy.rows[0].mismatches,
      iterations: ITERS,
      warmup: WARMUP,
      timings_median_ms: {
        cand_discovery: candDiscovery.median_ms,
        items_hydration_baseline: itemsBaseline.median_ms,
        items_hydration_optimized: itemsOptimized.median_ms,
        items_hydration_trade_heavy_baseline: itemsTradeHeavyBaseline.median_ms,
        items_hydration_trade_heavy_optimized: itemsTradeHeavyOptimized.median_ms,
        trade_payload_baseline: tradePayloadBaseline.median_ms,
        trade_payload_optimized: tradePayloadOptimized.median_ms,
        viewer_has_block_with_microbench: blockCheckOnly.median_ms,
        block_peers_array_microbench: blockPeersOnly.median_ms,
        full_rpc_baseline: fullRpc.median_ms,
        full_rpc_trades_filter: fullRpcTradesOnly.median_ms,
        trade_payload_baseline_viewer_with_block: tradePayloadBaselineBlocked.median_ms,
        trade_payload_optimized_viewer_with_block: tradePayloadOptimizedBlocked.median_ms,
      },
      ratios: {
        items_over_cand_baseline: Math.round((itemsBaseline.median_ms / candDiscovery.median_ms) * 100) / 100,
        items_over_cand_optimized: Math.round((itemsOptimized.median_ms / candDiscovery.median_ms) * 100) / 100,
        trade_payload_speedup:
          Math.round((tradePayloadBaseline.median_ms / Math.max(tradePayloadOptimized.median_ms, 0.01)) * 100) /
          100,
        items_speedup:
          Math.round((itemsBaseline.median_ms / Math.max(itemsOptimized.median_ms, 0.01)) * 100) / 100,
        items_share_of_full_rpc_pct:
          Math.round((itemsBaseline.median_ms / Math.max(fullRpc.median_ms, 0.01)) * 1000) / 10,
        trade_payload_speedup_blocked_viewer:
          Math.round(
            (tradePayloadBaselineBlocked.median_ms /
              Math.max(tradePayloadOptimizedBlocked.median_ms, 0.01)) *
              100
          ) / 100,
      },
      block_viewer: {
        id: VIEWER_BLOCK,
        block_peers_count: blockPeersBlockedViewer?.length ?? 0,
      },
      plan_signals_last_iter: {
        trade_payload_baseline: tradePayloadBaseline.plan_signals,
        trade_payload_optimized: tradePayloadOptimized.plan_signals,
        items_baseline: itemsBaseline.plan_signals,
        items_optimized: itemsOptimized.plan_signals,
      },
      security_notes: [
        "Optimized path skips viewer_has_block_with when p_block_peers is supplied; must match get_active_block_peer_ids() for auth.uid() in the same statement.",
        "profile_is_visible_to_viewer and profile_viewer_can_view_trades remain; RLS on trades is bypassed by SECURITY DEFINER read — visibility gates unchanged.",
        "Wrong or stale p_block_peers from caller could expose trade JSON for a blocked peer (caller-trust / RPC-internal wiring only).",
      ],
    }

    const out = path.join(__dirname, "artifacts/feed_trade_payload_block_peers_report.json")
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
