import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { resolveTradovateApiEnvironmentForOAuth } from "./tradovateApiEnvironment.ts"

function mockSupabase(apiEnvironment: string | null) {
  return {
    from() {
      return {
        select() {
          return this
        },
        eq() {
          return this
        },
        maybeSingle: async () => ({
          data: apiEnvironment != null ? { api_environment: apiEnvironment } : null,
        }),
      }
    },
  } as unknown as import("@supabase/supabase-js").SupabaseClient
}

describe("resolveTradovateApiEnvironmentForOAuth", () => {
  it("connect_new without client env uses demo OAuth default (not TRADOVATE_API_ENV)", async () => {
    const prev = process.env.TRADOVATE_API_ENV
    const prevOauth = process.env.TRADOVATE_OAUTH_DEFAULT_ENV
    process.env.TRADOVATE_API_ENV = "live"
    delete process.env.TRADOVATE_OAUTH_DEFAULT_ENV
    try {
      const env = await resolveTradovateApiEnvironmentForOAuth({
        supabase: mockSupabase(null),
        userId: "u1",
        oauthIntent: "connect_new",
        targetConnectionId: null,
        requestedEnvironment: null,
      })
      assert.equal(env, "demo")
    } finally {
      if (prev === undefined) delete process.env.TRADOVATE_API_ENV
      else process.env.TRADOVATE_API_ENV = prev
      if (prevOauth === undefined) delete process.env.TRADOVATE_OAUTH_DEFAULT_ENV
      else process.env.TRADOVATE_OAUTH_DEFAULT_ENV = prevOauth
    }
  })

  it("reconnect preserves stored environment when client omits apiEnvironment", async () => {
    const env = await resolveTradovateApiEnvironmentForOAuth({
      supabase: mockSupabase("demo"),
      userId: "u1",
      oauthIntent: "reconnect",
      targetConnectionId: "conn-1",
      requestedEnvironment: null,
    })
    assert.equal(env, "demo")
  })

  it("reconnect explicit apiEnvironment overrides stored connection environment", async () => {
    const env = await resolveTradovateApiEnvironmentForOAuth({
      supabase: mockSupabase("live"),
      userId: "u1",
      oauthIntent: "reconnect",
      targetConnectionId: "conn-1",
      requestedEnvironment: "demo",
    })
    assert.equal(env, "demo")
  })

  it("connect_new honors explicit client apiEnvironment", async () => {
    const env = await resolveTradovateApiEnvironmentForOAuth({
      supabase: mockSupabase(null),
      userId: "u1",
      oauthIntent: "connect_new",
      requestedEnvironment: "live",
    })
    assert.equal(env, "live")
  })
})
