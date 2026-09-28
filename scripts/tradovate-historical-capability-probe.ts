/**
 * Read-only Tradovate historical capability probes (syncrequest + Reporting API).
 *
 *   TRADOVATE_HISTORICAL_PROBE=1 npx tsx scripts/tradovate-historical-capability-probe.ts \
 *     --connectionId=6ff59f30-9d9e-494e-bfec-3f022205088b \
 *     --providerUserId=6693068 \
 *     --accountId=65788591
 */
import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { createClient } from "@supabase/supabase-js"
import {
  runTradovateReportingProbe,
  runTradovateSyncRequestProbe,
  TRADOVATE_REFERENCE_SEP2026_FILL_IDS,
} from "../lib/integrations/tradovate/tradovateHistoricalCapabilityProbe.ts"

function loadDotEnvLocal(): void {
  for (const name of [".env.local", ".env"]) {
    try {
      const raw = readFileSync(resolve(process.cwd(), name), "utf8")
      for (const line of raw.split("\n")) {
        const trimmed = line.trim()
        if (!trimmed || trimmed.startsWith("#")) continue
        const eq = trimmed.indexOf("=")
        if (eq <= 0) continue
        const key = trimmed.slice(0, eq).trim()
        let val = trimmed.slice(eq + 1).trim()
        if (
          (val.startsWith('"') && val.endsWith('"')) ||
          (val.startsWith("'") && val.endsWith("'"))
        ) {
          val = val.slice(1, -1)
        }
        if (process.env[key] == null || process.env[key] === "") {
          process.env[key] = val
        }
      }
    } catch {
      // optional
    }
  }
}

function argValue(name: string): string | undefined {
  const prefix = `--${name}=`
  for (const a of process.argv.slice(2)) {
    if (a.startsWith(prefix)) return a.slice(prefix.length).trim()
  }
  return undefined
}

async function main(): Promise<void> {
  if (process.env.TRADOVATE_HISTORICAL_PROBE !== "1") {
    console.error("Set TRADOVATE_HISTORICAL_PROBE=1 to run read-only probes.")
    process.exit(2)
  }

  loadDotEnvLocal()
  const supabaseUrl =
    process.env.SUPABASE_URL?.trim() ??
    process.env.NEXT_PUBLIC_SUPABASE_URL?.trim()
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim()
  if (!supabaseUrl || !serviceKey) {
    throw new Error("Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY")
  }

  const connectionId =
    argValue("connectionId") ?? "6ff59f30-9d9e-494e-bfec-3f022205088b"
  const providerUserId = Number(
    argValue("providerUserId") ?? "6693068"
  )
  const accountId = argValue("accountId") ?? "65788591"

  const supabase = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: conn, error } = await supabase
    .from("broker_integration_connections")
    .select("id, user_id, api_environment, provider_user_id, status")
    .eq("id", connectionId)
    .maybeSingle()

  if (error || !conn) {
    throw new Error(`Connection not found: ${connectionId}`)
  }

  const userId = String(conn.user_id)
  console.info(
    JSON.stringify({
      probe: "tradovate_historical_capability",
      connectionId,
      userId,
      apiEnvironment: conn.api_environment,
      providerUserIdFromDb: conn.provider_user_id,
      providerUserIdUsed: providerUserId,
      accountId,
      referenceFillIdCount: TRADOVATE_REFERENCE_SEP2026_FILL_IDS.length,
    })
  )

  const syncProbe = await runTradovateSyncRequestProbe(supabase, {
    userId,
    connectionId,
    providerUserId,
    accountId,
  })

  console.info(JSON.stringify({ probe: "user_syncrequest", ...syncProbe }, null, 2))

  const reportingProbe = await runTradovateReportingProbe(supabase, {
    userId,
    connectionId,
    accountId,
    startDate: "09/14/2026",
    endDate: "09/23/2026",
  })

  console.info(
    JSON.stringify({ probe: "reporting_api", ...reportingProbe }, null, 2)
  )
}

void main().catch((err) => {
  console.error("[tradovate-historical-probe] failed", err instanceof Error ? err.message : err)
  process.exit(1)
})
