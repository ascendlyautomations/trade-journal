import { describe, it } from "node:test"
import { decodeSessionBootstrapV1 } from "./contracts.ts"
import { sessionBootstrapFixture } from "./fixtures.ts"
import { compareSessionBootstraps, } from "./sessionBootstrapCompare.ts"
import { isBackendV2Enabled, listBackendV2Flags, resolveBackendV2Flag, __setBackendV2FlagForTests, __resetBackendV2FlagsForTests, } from "./flags.ts"
import assert from "node:assert/strict"

describe("Backend V2 session bootstrap contract", () => {
  it("includes session_profile for gate hydration", () => {
    const decoded = decodeSessionBootstrapV1(
      JSON.parse(JSON.stringify(sessionBootstrapFixture))
    )
    assert.equal(decoded.data.session_profile.username, "viewer")
    assert.equal(decoded.data.session_profile.onboarding_completed, true)
    assert.equal(decoded.data.viewer.entitlement.plan, "pro")
  })

  it("compare detects following_ids mismatch", () => {
    const rest = JSON.parse(JSON.stringify(sessionBootstrapFixture))
    const rpc = JSON.parse(JSON.stringify(sessionBootstrapFixture))
    rpc.data.following_ids = ["other"]
    const mismatches = compareSessionBootstraps(rest, rpc)
    assert.ok(mismatches.some((m) => m.path === "following_ids"))
  })

  it("session flag remains OFF by default", () => {
    __resetBackendV2FlagsForTests()
    const prev = process.env.NEXT_PUBLIC_BACKEND_V2_SESSION
    delete process.env.NEXT_PUBLIC_BACKEND_V2_SESSION
    try {
      assert.equal(resolveBackendV2Flag("session").source, "default")
      assert.equal(isBackendV2Enabled("session"), false)
      assert.equal(
        listBackendV2Flags().find((f) => f.key === "session")?.enabled,
        false
      )
    } finally {
      if (prev === undefined) delete process.env.NEXT_PUBLIC_BACKEND_V2_SESSION
      else process.env.NEXT_PUBLIC_BACKEND_V2_SESSION = prev
    }
  })

  it("env override enables session flag", () => {
    __resetBackendV2FlagsForTests()
    const prev = process.env.NEXT_PUBLIC_BACKEND_V2_SESSION
    process.env.NEXT_PUBLIC_BACKEND_V2_SESSION = "1"
    try {
      const resolved = resolveBackendV2Flag("session")
      assert.equal(resolved.enabled, true)
      assert.equal(resolved.source, "env")
    } finally {
      if (prev === undefined) delete process.env.NEXT_PUBLIC_BACKEND_V2_SESSION
      else process.env.NEXT_PUBLIC_BACKEND_V2_SESSION = prev
      __resetBackendV2FlagsForTests()
    }
  })
})
export {}
