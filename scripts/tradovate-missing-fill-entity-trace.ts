/**
 * READ-ONLY Tradovate entity trace for missing Performance fills.
 *
 * Local: requires INTEGRATION_CREDENTIALS_ENCRYPTION_KEY + Supabase service role.
 * Production (preferred): set TRADOVATE_ENTITY_TRACE=1 on Vercel, then:
 *   curl -X POST "$BASE/api/internal/tradovate/missing-fill-entity-trace" \
 *     -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
 *     -H "Content-Type: application/json" \
 *     -d '{"externalAccountId":"65788591"}'
 *
 * Gated — TRADOVATE_ENTITY_TRACE=1
 */
import { readFileSync } from "node:fs"
import { resolve } from "node:path"
import { createClient } from "@supabase/supabase-js"
import {
  formatTradovateMissingFillEntityTraceMatrix,
  resolveConnectedTradovateMapping,
  runTradovateMissingFillEntityTrace,
} from "../lib/integrations/tradovate/tradovateMissingFillEntityTrace.ts"

function loadDotEnvLocal(): void {
  for (const name of [".env.local", ".env.trace"]) {
    const path = resolve(process.cwd(), name)
    try {
      const raw = readFileSync(path, "utf8")
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
  if (process.env.TRADOVATE_ENTITY_TRACE !== "1") {
    console.error(
      "Refusing to run: set TRADOVATE_ENTITY_TRACE=1 (read-only diagnostic gate)."
    )
    process.exit(2)
  }

  loadDotEnvLocal()

  const remoteBase = argValue("remoteBase")?.replace(/\/$/, "")
  if (remoteBase) {
    const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim()
    if (!key) throw new Error("Missing SUPABASE_SERVICE_ROLE_KEY for remote trace.")
    const accountId = argValue("accountId") ?? "65788591"
    const res = await fetch(
      `${remoteBase}/api/internal/tradovate/missing-fill-entity-trace`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${key}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ externalAccountId: accountId }),
      }
    )
    const text = await res.text()
    if (!res.ok) {
      throw new Error(`Remote trace HTTP ${res.status}: ${text.slice(0, 400)}`)
    }
    const parsed = JSON.parse(text) as {
      ok: boolean
      matrixText?: string
      error?: string
    }
    if (!parsed.ok) {
      throw new Error(parsed.error ?? "remote_trace_failed")
    }
    console.info(parsed.matrixText ?? text)
    return
  }

  const url =
    process.env.NEXT_PUBLIC_SUPABASE_URL?.trim() ??
    process.env.SUPABASE_URL?.trim()
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim()
  if (!url || !key) {
    throw new Error("Missing Supabase URL or SUPABASE_SERVICE_ROLE_KEY.")
  }

  const supabase = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const accountId = argValue("accountId") ?? "65788591"
  const mapping = await resolveConnectedTradovateMapping(supabase, accountId)
  console.info(
    `[TradovateEntityTrace] accountId=${mapping.accountId} connectionId=${mapping.connectionId} mappingId=${mapping.mappingId}`
  )

  const result = await runTradovateMissingFillEntityTrace(supabase, mapping)

  console.info("[TradovateEntityTrace] section=fill/items")
  for (const row of result.fillItems) {
    console.info(`  fillId=${row.id} ${JSON.stringify(row)}`)
  }
  for (const id of Object.keys(result.fillListFound)) {
    console.info(
      `  fillId=${id} foundInList=${result.fillListFound[id]} totalRawCount=${result.fillListTotalCount}`
    )
  }
  console.info(formatTradovateMissingFillEntityTraceMatrix(result))
  console.info("[TradovateEntityTrace] done")
}

main().catch((err) => {
  console.error(
    "[TradovateEntityTrace] failed",
    err instanceof Error ? err.message : String(err)
  )
  process.exit(1)
})
