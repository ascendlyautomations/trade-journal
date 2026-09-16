/**
 * One-time maintenance: copy Rithmic username/system from legacy ciphertext into
 * broker_login_username / provider_display_name, then clear credentials_ciphertext.
 *
 * Usage (service role env required):
 *   npx tsx scripts/backfill-rithmic-transient-credentials.ts
 */
import { createClient } from "@supabase/supabase-js"
import {
  decryptIntegrationCredentials,
  isRithmicIntegrationCredentials,
} from "../lib/integrations/credentialEncryption"

async function main() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL?.trim()
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY?.trim()
  if (!url || !key) {
    throw new Error("Missing Supabase service role env.")
  }

  const supabase = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  })

  const { data: rows, error } = await supabase
    .from("broker_integration_connections")
    .select("id, credentials_ciphertext, broker_login_username, provider_display_name")
    .eq("provider", "rithmic")
    .not("credentials_ciphertext", "is", null)

  if (error) throw error
  if (!rows?.length) {
    console.info("No legacy Rithmic ciphertext rows.")
    return
  }

  let updated = 0
  for (const row of rows) {
    const ciphertext = row.credentials_ciphertext
    if (!ciphertext || typeof ciphertext !== "string") continue
    try {
      const payload = decryptIntegrationCredentials(ciphertext)
      if (!isRithmicIntegrationCredentials(payload)) continue
      const patch: Record<string, string | null> = {
        credentials_ciphertext: null,
        updated_at: new Date().toISOString(),
      }
      if (!row.broker_login_username?.trim()) {
        patch.broker_login_username = payload.username.trim()
      }
      if (!row.provider_display_name?.trim()) {
        patch.provider_display_name = payload.systemName.trim()
      }
      const { error: upErr } = await supabase
        .from("broker_integration_connections")
        .update(patch)
        .eq("id", row.id)
      if (upErr) throw upErr
      updated += 1
    } catch (err) {
      console.error("row_failed", row.id, err instanceof Error ? err.message : err)
    }
  }

  console.info(`Backfilled ${updated} Rithmic connection(s). Password material cleared.`)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
