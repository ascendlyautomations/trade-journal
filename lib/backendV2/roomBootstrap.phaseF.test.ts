import { describe, it, beforeEach } from "node:test"
import { decodeRoomBootstrapV1 } from "./roomContracts.ts"
import { roomContractFixtures } from "./roomContractFixtures.ts"
import { roomBootstrapCacheKey, readRoomBootstrapCache, writeRoomBootstrapCache, clearRoomBootstrapCache, } from "./roomBootstrapCache.ts"
import { beginRoomBootstrapFlight, getRoomBootstrapFlight, __resetRoomBootstrapFlightsForTests, } from "./roomBootstrapSingleFlight.ts"
import { isRoomBootstrapRpcUnavailable } from "./roomRpcCompat.ts"
import { BackendV2RpcError } from "./rpcClient.ts"
import { __setBackendV2FlagForTests, __resetBackendV2FlagsForTests, isBackendV2Enabled, } from "./flags.ts"
import { applyRoomBootstrapToCommunityState, roomBootstrapEffectsKey, } from "./roomBootstrapApply.ts"
import assert from "node:assert/strict"
import type { SetStateAction } from "react"

describe("Phase F — Room bootstrap contract", () => {
  for (const [name, fixture] of Object.entries(roomContractFixtures)) {
    it(`decodes ${name} fixture`, () => {
      const decoded = decodeRoomBootstrapV1(JSON.parse(JSON.stringify(fixture)))
      assert.equal(decoded.meta.contract_version, "v1")
      assert.equal(decoded.data.room.id, fixture.data.room.id)
    })
  }

  it("mark-read fixture clears unread", () => {
    const decoded = decodeRoomBootstrapV1(
      JSON.parse(JSON.stringify(roomContractFixtures.ownerOpenMarkRead))
    )
    assert.equal(decoded.data.mark_read.applied, true)
    assert.equal(decoded.data.unread_count, 0)
  })
})

describe("Phase F — Room bootstrap cache + single-flight", () => {
  beforeEach(() => {
    clearRoomBootstrapCache()
    __resetRoomBootstrapFlightsForTests()
    __resetBackendV2FlagsForTests()
  })

  it("cache key is per viewer room section", () => {
    const key = roomBootstrapCacheKey({
      userId: "u1",
      roomId: "r1",
      sectionId: "s1",
    })
    assert.equal(key, "u1|r1|s1")
  })

  it("single-flight dedupes concurrent loads", async () => {
    let calls = 0
    const key = "u1|r1|auto"
    const p1 = beginRoomBootstrapFlight(key, "u1", async () => {
      calls += 1
      await new Promise((r) => setTimeout(r, 10))
      return { ok: true }
    })
    const p2 = beginRoomBootstrapFlight(key, "u1", async () => {
      calls += 1
      return { ok: false }
    })
    assert.equal(getRoomBootstrapFlight(key), p1)
    const [a, b] = await Promise.all([p1, p2])
    assert.deepEqual(a, b)
    assert.equal(calls, 1)
  })

  it("logout clears viewer-scoped cache", () => {
    const fixture = decodeRoomBootstrapV1(
      JSON.parse(JSON.stringify(roomContractFixtures.emptyRoom))
    )
    const key = roomBootstrapCacheKey({ userId: "u1", roomId: "r1" })
    writeRoomBootstrapCache(key, "u1", "r1", fixture, "rpc")
    clearRoomBootstrapCache("u1")
    assert.equal(readRoomBootstrapCache(key), null)
  })
})

describe("Phase F — Room RPC compat", () => {
  it("detects missing RPC", () => {
    assert.equal(
      isRoomBootstrapRpcUnavailable(
        new BackendV2RpcError(
          "PGRST202",
          "Could not find public.rpc_v1_room_bootstrap",
          "rpc_v1_room_bootstrap"
        )
      ),
      true
    )
  })

  it("detects 42703 schema contract failure", () => {
    assert.equal(
      isRoomBootstrapRpcUnavailable(
        new BackendV2RpcError(
          "42703",
          "column r.is_public does not exist",
          "rpc_v1_room_bootstrap"
        )
      ),
      true
    )
  })
})

describe("Phase F — apply bootstrap patches unread locally", () => {
  it("does not require unread refetch after mark read", () => {
    const decoded = decodeRoomBootstrapV1(
      JSON.parse(JSON.stringify(roomContractFixtures.ownerOpenMarkRead))
    )
    let unread: Record<string, boolean> = { r1: true }
    const markedRef = { current: null as string | null }
    applyRoomBootstrapToCommunityState(decoded, "r1", "u1", {
      setSections: () => {},
      setSelectedSectionId: () => {},
      setPinnedMessages: () => {},
      setMessages: () => {},
      setHasOlderMessages: () => {},
      setLoadingMessages: () => {},
      setRoomNotificationsEnabled: () => {},
      setChannelNotificationPrefs: () => {},
      setActiveMembers: () => {},
      setLeftMembers: () => {},
      setUnreadByRoomId: (fn: SetStateAction<Record<string, boolean>>) => {
        unread = typeof fn === "function" ? fn(unread) : fn
      },
      patchRoomSectionsInSession: () => {},
      patchRoomMessagesInSession: () => {},
      buildRoomMessagesCacheKey: () => "k",
      messagesByRoomRef: { current: {} },
      setMessagesByRoom: () => {},
      markedReadRoomKeyRef: markedRef,
    })
    assert.equal(unread.r1, false)
    assert.equal(markedRef.current, "r1:u1")
    assert.equal(roomBootstrapEffectsKey("r1"), "r1")
  })
})

describe("Phase F — flag gating", () => {
  beforeEach(() => {
    __resetBackendV2FlagsForTests()
  })

  it("rooms flag defaults off", () => {
    assert.equal(isBackendV2Enabled("rooms"), false)
  })
})
export {}
