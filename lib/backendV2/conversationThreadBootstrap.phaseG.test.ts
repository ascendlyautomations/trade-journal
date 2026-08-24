import { describe, it, beforeEach } from "node:test"
import { decodeConversationThreadBootstrapV1 } from "./conversationThreadContracts.ts"
import { conversationThreadContractFixtures } from "./conversationThreadContractFixtures.ts"
import { conversationThreadCacheKey, readConversationThreadCache, writeConversationThreadCache, clearConversationThreadCache, } from "./conversationThreadBootstrapCache.ts"
import { beginConversationThreadFlight, getConversationThreadFlight, __resetConversationThreadFlightsForTests, } from "./conversationThreadBootstrapSingleFlight.ts"
import { isConversationThreadRpcUnavailable } from "./conversationThreadRpcCompat.ts"
import { BackendV2RpcError } from "./rpcClient.ts"
import { __setBackendV2FlagForTests, __resetBackendV2FlagsForTests, isBackendV2Enabled, } from "./flags.ts"
import { registerConversationThreadAlias, resolveConversationThreadAlias, clearConversationThreadAliases, } from "./conversationThreadAliasCache.ts"
import assert from "node:assert/strict"

describe("Phase G — Conversation thread contract", () => {
  for (const [name, fixture] of Object.entries(conversationThreadContractFixtures)) {
    it(`decodes ${name} fixture`, () => {
      const decoded = decodeConversationThreadBootstrapV1(
        JSON.parse(JSON.stringify(fixture))
      )
      assert.equal(decoded.meta.contract_version, "v1")
      assert.equal(decoded.data.conversation.id, fixture.data.conversation.id)
    })
  }

  it("open fixture marks read and clears unread", () => {
    const decoded = decodeConversationThreadBootstrapV1(
      JSON.parse(JSON.stringify(conversationThreadContractFixtures.directOpen))
    )
    assert.equal(decoded.data.mark_read.applied, true)
    assert.equal(decoded.data.unread_count, 0)
  })

  it("pagination fixture does not mark read", () => {
    const decoded = decodeConversationThreadBootstrapV1(
      JSON.parse(JSON.stringify(conversationThreadContractFixtures.groupPagination))
    )
    assert.equal(decoded.data.mark_read.applied, false)
  })
})

describe("Phase G — Conversation thread cache + single-flight", () => {
  beforeEach(() => {
    clearConversationThreadCache()
    __resetConversationThreadFlightsForTests()
    __resetBackendV2FlagsForTests()
    clearConversationThreadAliases()
  })

  it("cache key is per viewer conversation", () => {
    const key = conversationThreadCacheKey({
      userId: "u1",
      conversationId: "c1",
    })
    assert.equal(key, "u1|c1")
  })

  it("single-flight dedupes concurrent loads", async () => {
    let calls = 0
    const key = "u1|c1"
    const p1 = beginConversationThreadFlight(key, "u1", async () => {
      calls += 1
      await new Promise((r) => setTimeout(r, 10))
      return { ok: true }
    })
    const p2 = beginConversationThreadFlight(key, "u1", async () => {
      calls += 1
      return { ok: false }
    })
    assert.equal(getConversationThreadFlight(key), p1)
    const [a, b] = await Promise.all([p1, p2])
    assert.deepEqual(a, b)
    assert.equal(calls, 1)
  })

  it("logout clears viewer-scoped cache", () => {
    const fixture = JSON.parse(
      JSON.stringify(conversationThreadContractFixtures.directOpen)
    )
    writeConversationThreadCache("u1|c1", "u1", "c1", fixture)
    clearConversationThreadCache("u1")
    assert.equal(readConversationThreadCache("u1|c1"), null)
  })

  it("username alias resolves per viewer without cross-viewer leak", () => {
    registerConversationThreadAlias("u1", "peername", "convo-1")
    assert.equal(resolveConversationThreadAlias("u1", "peername"), "convo-1")
    assert.equal(resolveConversationThreadAlias("u2", "peername"), null)
  })
})

describe("Phase G — Conversation thread RPC compat", () => {
  it("detects missing RPC", () => {
    const err = new BackendV2RpcError(
      "PGRST202",
      "Could not find public.rpc_v1_conversation_thread_bootstrap",
      "rpc_v1_conversation_thread_bootstrap"
    )
    assert.equal(isConversationThreadRpcUnavailable(err), true)
  })
})

describe("Phase G — feature flag", () => {
  beforeEach(() => {
    __resetBackendV2FlagsForTests()
  })

  it("messageThreads flag resolves via test override", () => {
    __setBackendV2FlagForTests("messageThreads", true)
    assert.equal(isBackendV2Enabled("messageThreads"), true)
  })
})
export {}
