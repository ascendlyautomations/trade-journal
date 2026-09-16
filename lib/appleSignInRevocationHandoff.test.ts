import { describe, it, mock, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { generateKeyPairSync } from "node:crypto"
import { revokeAppleSignInBeforeUserDelete } from "./appleSignInRevocation.ts"
import {
  encryptIntegrationCredentials,
} from "./integrations/credentialEncryption.ts"

describe("appleSignInRevocation handoff", () => {
  const envBackup = { ...process.env }

  beforeEach(() => {
    process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY = Buffer.alloc(32, 4).toString(
      "base64url"
    )
    const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" })
    process.env.APPLE_SIGN_IN_KEY_ID = "KEY1"
    process.env.APPLE_SIGN_IN_PRIVATE_KEY = privateKey
      .export({ type: "pkcs8", format: "pem" })
      .toString()
    process.env.APPLE_SIGN_IN_CLIENT_ID = "com.tradetraxs.TradeTraxs"
  })

  afterEach(() => {
    process.env = { ...envBackup }
    mock.reset()
  })

  it("queues existing ciphertext before deleting credentials on retryable revoke failure", async () => {
    const ciphertext = encryptIntegrationCredentials({
      kind: "apple_sign_in_refresh",
      refresh_token: "rt-handoff",
    })
    let insertedCiphertext: string | null = null
    let credentialsDeleted = false
    const fetchImpl = mock.fn(async () => new Response("", { status: 503 }))

    const supabase = {
      auth: {
        admin: {
          getUserById: async () => ({
            data: { user: { id: "u1", identities: [{ provider: "apple" }] } },
          }),
        },
      },
      from: (table: string) => ({
        select: () => ({
          eq: () => ({
            maybeSingle: async () =>
              table === "apple_sign_in_credentials"
                ? {
                    data: {
                      client_id: "com.tradetraxs.TradeTraxs",
                      refresh_token_ciphertext: ciphertext,
                    },
                    error: null,
                  }
                : { data: null, error: null },
          }),
        }),
        insert: (row: { refresh_token_ciphertext: string }) => {
          if (table === "apple_sign_in_revoke_queue") {
            insertedCiphertext = row.refresh_token_ciphertext
          }
          return Promise.resolve({ error: null })
        },
        delete: () => ({
          eq: async () => {
            if (table === "apple_sign_in_credentials") credentialsDeleted = true
            return { error: null }
          },
        }),
      }),
    }

    // Patch fetch on revoke path via global - revokeAppleRefreshToken uses fetch
    const originalFetch = globalThis.fetch
    globalThis.fetch = fetchImpl as unknown as typeof fetch
    try {
      const outcome = await revokeAppleSignInBeforeUserDelete(supabase as never, "u1")
      assert.equal(outcome, "queued_for_retry")
      assert.equal(insertedCiphertext, ciphertext)
      assert.equal(credentialsDeleted, true)
    } finally {
      globalThis.fetch = originalFetch
    }
  })

  it("does not report queued when insert fails", async () => {
    const ciphertext = encryptIntegrationCredentials({
      kind: "apple_sign_in_refresh",
      refresh_token: "rt-fail",
    })

    const supabase = {
      auth: {
        admin: {
          getUserById: async () => ({
            data: { user: { id: "u1", identities: [{ provider: "apple" }] } },
          }),
        },
      },
      from: (table: string) => ({
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({
              data: {
                client_id: "com.tradetraxs.TradeTraxs",
                refresh_token_ciphertext: ciphertext,
              },
              error: null,
            }),
          }),
        }),
        insert: () => Promise.resolve({ error: { message: "db down" } }),
        delete: () => ({
          eq: async () => ({ error: null }),
        }),
      }),
    }

    const originalFetch = globalThis.fetch
    globalThis.fetch = mock.fn(async () => new Response("", { status: 503 })) as unknown as typeof fetch
    try {
      const outcome = await revokeAppleSignInBeforeUserDelete(supabase as never, "u1")
      assert.equal(outcome, "queue_persistence_failed")
    } finally {
      globalThis.fetch = originalFetch
    }
  })
})

export {}
