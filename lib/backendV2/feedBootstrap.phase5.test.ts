import { describe, it, beforeEach } from "node:test"
import { isBackendV2Enabled, resolveBackendV2Flag, __setBackendV2FlagForTests, __resetBackendV2FlagsForTests, } from "./flags.ts"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))

describe("Backend V2 feed cutover (Phase 5)", () => {
  beforeEach(() => {
    __resetBackendV2FlagsForTests()
  })

  it("feed flag OFF is the gate that skips rpc_v1_feed_bootstrap", () => {
    __setBackendV2FlagForTests("feed", false)
    const resolved = resolveBackendV2Flag("feed")
    assert.equal(resolved.enabled, false)
    assert.equal(isBackendV2Enabled("feed"), false)
  })

  it("feed flag ON enables the RPC cutover path", () => {
    __setBackendV2FlagForTests("feed", true)
    assert.equal(isBackendV2Enabled("feed"), true)
    assert.equal(resolveBackendV2Flag("feed").source, "test")
  })

  it("feed page wires loadPosts through isBackendV2Enabled(feed) before REST", () => {
    const pagePath = path.join(
      __dirname,
      "../../app/(app)/feed/page.tsx"
    )
    const src = fs.readFileSync(pagePath, "utf8")
    assert.match(src, /isBackendV2Enabled\("feed"\)/)
    assert.match(src, /loadFeedBootstrapForUser/)
    assert.match(src, /topUpMergedFeedBuffer/)
    // In loadPosts, RPC path must run before legacy merged REST fan-out.
    const rpcLoadIdx = src.indexOf("loadFeedBootstrapForUser(supabase")
    const restIdx = src.indexOf("topUpMergedFeedBuffer(supabase")
    assert.ok(rpcLoadIdx > 0, "expected loadFeedBootstrapForUser call")
    assert.ok(restIdx > rpcLoadIdx, "REST fan-out must remain after RPC gate")
  })
})
export {}
