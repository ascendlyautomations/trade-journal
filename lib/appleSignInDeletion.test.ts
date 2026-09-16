import { describe, it, beforeEach, afterEach } from "node:test"
import assert from "node:assert/strict"
import { generateKeyPairSync } from "node:crypto"
import { revokeAppleSignInBeforeUserDelete } from "./appleSignInRevocation.ts"

describe("revokeAppleSignInBeforeUserDelete", () => {
  const envBackup = { ...process.env }

  beforeEach(() => {
    process.env.INTEGRATION_CREDENTIALS_ENCRYPTION_KEY = Buffer.alloc(32, 2).toString(
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
  })

  it("returns not_applicable for non-Apple users", async () => {
    const supabase = {
      auth: {
        admin: {
          getUserById: async () => ({
            data: { user: { id: "u1", identities: [{ provider: "email" }] } },
          }),
        },
      },
    }
    const outcome = await revokeAppleSignInBeforeUserDelete(supabase as never, "u1")
    assert.equal(outcome, "not_applicable")
  })

  it("returns legacy_no_token when Apple user has no stored refresh token", async () => {
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
                ? { data: null, error: null }
                : { data: null, error: null },
          }),
        }),
        delete: () => ({
          eq: async () => ({ error: null }),
        }),
      }),
    }
    const outcome = await revokeAppleSignInBeforeUserDelete(supabase as never, "u1")
    assert.equal(outcome, "legacy_no_token")
  })
})

export {}
