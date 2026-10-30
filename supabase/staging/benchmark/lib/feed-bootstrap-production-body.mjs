import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(__dirname, "../../../..")

export function buildProductionShapedBody() {
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
