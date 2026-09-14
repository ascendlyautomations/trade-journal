/**
 * Long-lived Tradovate user-sync worker (NOT deployable on Vercel serverless).
 *
 * Run: npm run broker-sync-worker
 * Requires: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, INTEGRATION_CREDENTIALS_ENCRYPTION_KEY,
 *           TRADOVATE_* OAuth env (same as web app).
 */
import { createClient, type SupabaseClient } from "@supabase/supabase-js"
import {
  TradovateConnectionAutoSyncSession,
  type ActiveTradovateConnection,
} from "../../lib/integrations/tradovate/tradovateConnectionAutoSync.ts"
import { logTradovateSync } from "../../lib/integrations/tradovate/tradovateSyncLogger.ts"

const REFRESH_CONNECTIONS_MS = 60_000

function requireEnv(name: string): string {
  const v = process.env[name]?.trim()
  if (!v) throw new Error(`Missing env ${name}`)
  return v
}

function createServiceSupabase(): SupabaseClient {
  return createClient(requireEnv("SUPABASE_URL"), requireEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  })
}

async function loadActiveConnections(
  supabase: SupabaseClient
): Promise<ActiveTradovateConnection[]> {
  const { data, error } = await supabase
    .from("broker_integration_connections")
    .select(
      "id, user_id, api_environment, provider_user_id, credentials_ciphertext, access_token_expires_at, status"
    )
    .eq("provider", "tradovate")
    .eq("status", "connected")
    .not("credentials_ciphertext", "is", null)
    .not("provider_user_id", "is", null)

  if (error) throw new Error(error.message)
  return (data ?? [])
    .filter(
      (row) =>
        row.api_environment === "demo" ||
        row.api_environment === "live"
    )
    .map((row) => ({
      id: String(row.id),
      user_id: String(row.user_id),
      api_environment: row.api_environment as "demo" | "live",
      provider_user_id: String(row.provider_user_id),
      credentials_ciphertext: String(row.credentials_ciphertext),
      access_token_expires_at: row.access_token_expires_at,
    }))
}

async function main(): Promise<void> {
  const supabase = createServiceSupabase()
  const sessions = new Map<string, TradovateConnectionAutoSyncSession>()

  async function reconcileSessions(): Promise<void> {
    const connections = await loadActiveConnections(supabase)
    const activeIds = new Set(connections.map((c) => c.id))

    for (const [id, session] of sessions) {
      if (!activeIds.has(id)) {
        session.stop()
        sessions.delete(id)
        logTradovateSync("connection_session_stopped", { connectionId: id })
      }
    }

    for (const connection of connections) {
      if (sessions.has(connection.id)) continue
      const session = new TradovateConnectionAutoSyncSession(supabase, connection)
      sessions.set(connection.id, session)
      logTradovateSync("connection_session_start", { connectionId: connection.id })
      void session.start()
    }
  }

  logTradovateSync("worker_started", { provider: "tradovate" })
  await reconcileSessions()
  setInterval(() => {
    void reconcileSessions()
  }, REFRESH_CONNECTIONS_MS)
}

void main().catch((err) => {
  console.error("[tradovate-sync-worker] fatal", err)
  process.exit(1)
})
