import { describe, it, beforeEach } from "node:test"
import { messagesBootstrapFixture, } from "./fixtures.ts"
import { compareMessagingBootstraps, } from "./messagingBootstrapCompare.ts"
import { messagingBootstrapCacheKey, readMessagingBootstrapCache, writeMessagingBootstrapCache, clearMessagingBootstrapCache, } from "./messagingBootstrapCache.ts"
import { beginMessagingBootstrapFlight, __resetMessagingBootstrapFlightsForTests, } from "./messagingBootstrapSingleFlight.ts"
import { decodeMessagesBootstrapV1, } from "./contracts.ts"
import { isBackendV2Enabled, resolveBackendV2Flag, __setBackendV2FlagForTests, __resetBackendV2FlagsForTests, } from "./flags.ts"
import { BackendV2RpcNames } from "./versioning.ts"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))

describe("Backend V2 messaging bootstrap (Phase 6)", () => {
  beforeEach(() => {
    clearMessagingBootstrapCache()
    __resetMessagingBootstrapFlightsForTests()
    __resetBackendV2FlagsForTests()
  })

  it("decodes fixture with conversations + dm_unread_total", () => {
    const decoded = decodeMessagesBootstrapV1(
      JSON.parse(JSON.stringify(messagesBootstrapFixture))
    )
    assert.equal(decoded.data.dm_unread_total, 1)
    assert.ok(Array.isArray(decoded.data.conversations))
    assert.equal(decoded.data.page_meta.returned, 1)
  })

  it("messages flag defaults OFF", () => {
    assert.equal(isBackendV2Enabled("messages"), false)
  })

  it("messages flag accepts MESSAGES or MESSAGING env keys in flags.ts", () => {
    const flagsSrc = fs.readFileSync(
      path.join(__dirname, "flags.ts"),
      "utf8"
    )
    assert.match(flagsSrc, /NEXT_PUBLIC_BACKEND_V2_MESSAGES/)
    assert.match(flagsSrc, /NEXT_PUBLIC_BACKEND_V2_MESSAGING/)
  })

  it("RPC name is rpc_v2_messaging_bootstrap with V1 fallback constant", () => {
    assert.equal(BackendV2RpcNames.messaging, "rpc_v2_messaging_bootstrap")
    assert.equal(BackendV2RpcNames.messagingV1, "rpc_v1_messaging_bootstrap")
  })

  it("compare detects conversation id mismatch", () => {
    const rest = JSON.parse(JSON.stringify(messagesBootstrapFixture))
    const rpc = JSON.parse(JSON.stringify(messagesBootstrapFixture))
    rpc.data.conversations = []
    const mismatches = compareMessagingBootstraps(rest, rpc)
    assert.ok(mismatches.some((m) => m.path === "conversations.ids"))
  })

  it("cache is keyed by user + cursor", () => {
    const uid = messagesBootstrapFixture.meta.viewer_id
    assert.ok(uid)
    const keyA = messagingBootstrapCacheKey({ userId: uid, cursor: null })
    const keyB = messagingBootstrapCacheKey({
      userId: uid,
      cursor: "2026-08-19T19:00:00.000Z",
    })
    writeMessagingBootstrapCache(keyA, uid, messagesBootstrapFixture, "rpc")
    assert.ok(readMessagingBootstrapCache(keyA))
    assert.equal(readMessagingBootstrapCache(keyB), null)
  })

  it("single-flight shares one start", async () => {
    let starts = 0
    const start = async () => {
      starts += 1
      await new Promise((r) => setTimeout(r, 15))
      return { ok: true, starts }
    }
    const [a, b] = await Promise.all([
      beginMessagingBootstrapFlight("k1", "u1", start),
      beginMessagingBootstrapFlight("k1", "u1", start),
    ])
    assert.equal(starts, 1)
    assert.equal(a.starts, 1)
    assert.equal(b.starts, 1)
  })
})

describe("Backend V2 messaging cutover wiring (Phase 6.1)", () => {
  beforeEach(() => {
    __resetBackendV2FlagsForTests()
  })

  it("messages flag OFF is the gate that skips messaging RPC cutover", () => {
    __setBackendV2FlagForTests("messages", false)
    const resolved = resolveBackendV2Flag("messages")
    assert.equal(resolved.enabled, false)
    assert.equal(isBackendV2Enabled("messages"), false)
  })

  it("messages flag ON enables the RPC cutover path", () => {
    __setBackendV2FlagForTests("messages", true)
    assert.equal(isBackendV2Enabled("messages"), true)
    assert.equal(resolveBackendV2Flag("messages").source, "test")
  })

  it("messages page wires fetchConversations through isBackendV2Enabled(messages) before REST", () => {
    const pagePath = path.join(
      __dirname,
      "../../app/(app)/messages/page.tsx"
    )
    const src = fs.readFileSync(pagePath, "utf8")
    assert.match(src, /isBackendV2Enabled\("messages"\)/)
    assert.match(src, /loadMessagingBootstrapForUser/)
    assert.match(src, /patchSessionBadges/)
    const rpcLoadIdx = src.indexOf("loadMessagingBootstrapForUser(supabase")
    const restIdx = src.indexOf("fetchUserDmConversations(supabase")
    assert.ok(rpcLoadIdx > 0, "expected loadMessagingBootstrapForUser call")
    assert.ok(restIdx > rpcLoadIdx, "REST fan-out must remain after RPC gate")
  })

  it("repository calls BackendV2RpcNames.messaging via callKnown", () => {
    const repoPath = path.join(__dirname, "messagingBootstrapRepository.ts")
    const src = fs.readFileSync(repoPath, "utf8")
    assert.match(src, /BackendV2RpcNames\.messaging/)
    assert.match(src, /BackendV2RpcNames\.messagingV1/)
    assert.match(src, /isMessagingV2Unavailable/)
  })
})
export {}
