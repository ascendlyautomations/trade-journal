/**
 * Live schema probe: accounts.id, trades.account_id, trigger + function body.
 * Uses Management API if SUPABASE_ACCESS_TOKEN is set; else PostgREST OpenAPI;
 * else postgres if SUPABASE_DB_PASSWORD / DATABASE_URL is set.
 */
import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { createClient } from "@supabase/supabase-js"

function loadEnv() {
  const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
  const env = {}
  for (const line of raw.split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue
    const i = line.indexOf("=")
    if (i < 1) continue
    const key = line.slice(0, i).trim()
    let val = line.slice(i + 1).trim()
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1)
    }
    env[key] = val
  }
  return env
}

const SQL = `
select 'column' as kind,
  c.table_name,
  c.column_name,
  c.data_type,
  c.udt_name,
  c.is_nullable
from information_schema.columns c
where c.table_schema = 'public'
  and (
    (c.table_name = 'accounts' and c.column_name = 'id')
    or (c.table_name = 'trades' and c.column_name = 'account_id')
  )

union all

select 'trigger' as kind,
  t.event_object_table as table_name,
  t.trigger_name as column_name,
  t.action_timing || ' ' || array_to_string(ARRAY(
    select e.event_manipulation
    from information_schema.triggers e
    where e.trigger_schema = t.trigger_schema
      and e.trigger_name = t.trigger_name
      and e.event_object_table = t.event_object_table
  ), ',') as data_type,
  t.action_statement as udt_name,
  null as is_nullable
from information_schema.triggers t
where t.trigger_schema = 'public'
  and t.event_object_table = 'trades'
  and t.trigger_name = 'trades_enforce_account_can_add_trades'

union all

select 'function' as kind,
  'trades_enforce_account_can_add_trades' as table_name,
  p.proname as column_name,
  pg_get_function_identity_arguments(p.oid) as data_type,
  pg_get_functiondef(p.oid) as udt_name,
  null as is_nullable
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'trades_enforce_account_can_add_trades'

union all

select 'migration' as kind,
  coalesce(version, name) as table_name,
  name as column_name,
  coalesce(version, '') as data_type,
  coalesce(name, '') as udt_name,
  null as is_nullable
from supabase_migrations.schema_migrations
order by 1, 2, 3;
`

async function runViaManagementApi(accessToken, ref, sql) {
  const response = await fetch(
    `https://api.supabase.com/v1/projects/${ref}/database/query`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ query: sql }),
    }
  )
  const text = await response.text()
  if (!response.ok) {
    throw new Error(`Management API ${response.status}: ${text}`)
  }
  return JSON.parse(text)
}

async function runViaPg(connectionString, sql) {
  const pg = await import("pg")
  const client = new pg.default.Client({
    connectionString,
    ssl: { rejectUnauthorized: false },
  })
  await client.connect()
  try {
    const result = await client.query(sql)
    return result.rows
  } finally {
    await client.end()
  }
}

async function openApiProbe(env) {
  const res = await fetch(`${env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/`, {
    headers: {
      apikey: env.SUPABASE_SERVICE_ROLE_KEY,
      Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      Accept: "application/openapi+json",
    },
  })
  const j = await res.json()
  const defs = j.definitions || j.components?.schemas || {}
  const out = {}
  for (const name of ["accounts", "trades"]) {
    const props = defs[name]?.properties || {}
    out[name] = {}
    for (const col of ["id", "account_id", "user_id", "can_add_trades"]) {
      if (props[col]) out[name][col] = props[col]
    }
  }
  return { status: res.status, out }
}

const env = loadEnv()
const ref = env.NEXT_PUBLIC_SUPABASE_URL?.match(/https:\/\/([^.]+)/)?.[1]
const accessToken = env.SUPABASE_ACCESS_TOKEN
const dbUrl =
  env.DATABASE_URL ||
  (env.SUPABASE_DB_PASSWORD && ref
    ? `postgresql://postgres.${ref}:${encodeURIComponent(env.SUPABASE_DB_PASSWORD)}@aws-1-us-east-2.pooler.supabase.com:6543/postgres`
    : null)

console.log("project_ref:", ref)
console.log(
  "auth:",
  accessToken
    ? "SUPABASE_ACCESS_TOKEN"
    : dbUrl
      ? "DATABASE_URL/SUPABASE_DB_PASSWORD"
      : "none"
)

if (accessToken && ref) {
  const rows = await runViaManagementApi(accessToken, ref, SQL)
  console.log(JSON.stringify(rows, null, 2))
} else if (dbUrl) {
  const rows = await runViaPg(dbUrl, SQL)
  console.log(JSON.stringify(rows, null, 2))
} else {
  console.log("FALLBACK_OPENAPI_ONLY")
  const probe = await openApiProbe(env)
  console.log(JSON.stringify(probe, null, 2))

  // Also try selecting one row to see runtime types via JS
  const supabase = createClient(
    env.NEXT_PUBLIC_SUPABASE_URL,
    env.SUPABASE_SERVICE_ROLE_KEY
  )
  const { data: acct, error: aErr } = await supabase
    .from("accounts")
    .select("id, can_add_trades")
    .limit(1)
  const { data: trade, error: tErr } = await supabase
    .from("trades")
    .select("account_id")
    .not("account_id", "is", null)
    .limit(1)
  console.log(
    "sample_accounts",
    aErr?.message || {
      id: acct?.[0]?.id,
      id_typeof: typeof acct?.[0]?.id,
      can_add_trades: acct?.[0]?.can_add_trades,
    }
  )
  console.log(
    "sample_trades",
    tErr?.message || {
      account_id: trade?.[0]?.account_id,
      account_id_typeof: typeof trade?.[0]?.account_id,
    }
  )
  process.exitCode = 2
}
