import { describe, it, beforeEach } from "node:test"
import { decodeRoomBootstrapV1, RoomBootstrapContractError, } from "./roomContracts.ts"
import { roomContractFixtures } from "./roomContractFixtures.ts"
import { isRoomBootstrapRpcUnavailable, isRoomBootstrapSchemaContractError, isRoomBootstrapTransientError, } from "./roomRpcCompat.ts"
import { BackendV2RpcError } from "./rpcClient.ts"
import { isRoomBootstrapRpcCachedUnavailable, markRoomBootstrapRpcUnavailable, clearRoomBootstrapRpcUnavailableCache, __resetRoomBootstrapRpcAvailabilityForTests, } from "./roomV1Availability.ts"
import { readRoomBootstrapCache, writeRoomBootstrapCache, clearRoomBootstrapCache, roomBootstrapCacheKey, } from "./roomBootstrapCache.ts"
import assert from "node:assert/strict"

describe("Phase F regression — schema contract errors", () => {
  beforeEach(() => {
    __resetRoomBootstrapRpcAvailabilityForTests()
    clearRoomBootstrapCache()
  })

  it("42703 is a schema-contract incompatibility", () => {
    const err = new BackendV2RpcError(
      "42703",
      "column r.is_public does not exist",
      "rpc_v1_room_bootstrap"
    )
    assert.equal(isRoomBootstrapSchemaContractError(err), true)
    assert.equal(isRoomBootstrapRpcUnavailable(err), true)
  })

  it("42703 is not treated as transient", () => {
    const err = new BackendV2RpcError(
      "42703",
      "column r.is_public does not exist",
      "rpc_v1_room_bootstrap"
    )
    assert.equal(isRoomBootstrapTransientError(err), false)
  })

  it("500 is transient and not legacy-fallback eligible", () => {
    const err = new BackendV2RpcError(
      "500",
      "internal server error",
      "rpc_v1_room_bootstrap"
    )
    assert.equal(isRoomBootstrapTransientError(err), true)
    assert.equal(isRoomBootstrapRpcUnavailable(err), false)
  })

  it("marks RPC unavailable once per session after schema error", () => {
    markRoomBootstrapRpcUnavailable()
    assert.equal(isRoomBootstrapRpcCachedUnavailable(), true)
    clearRoomBootstrapRpcUnavailableCache()
    assert.equal(isRoomBootstrapRpcCachedUnavailable(), false)
  })

  it("missing messages array throws contract error (not empty room)", () => {
    const broken = JSON.parse(
      JSON.stringify(roomContractFixtures.memberWithSections)
    )
    delete broken.data.messages
    assert.throws(
      () => decodeRoomBootstrapV1(broken),
      (err) => err instanceof RoomBootstrapContractError
    )
  })

  it("successful empty room keeps explicit empty arrays", () => {
    const decoded = decodeRoomBootstrapV1(
      JSON.parse(JSON.stringify(roomContractFixtures.emptyRoom))
    )
    assert.deepEqual(decoded.data.messages, [])
    assert.deepEqual(decoded.data.pinned_messages, [])
  })

  it("successful non-empty room preserves message rows", () => {
    const decoded = decodeRoomBootstrapV1(
      JSON.parse(JSON.stringify(roomContractFixtures.memberWithSections))
    )
    assert.ok(decoded.data.messages.length > 0)
    assert.equal(decoded.data.messages[0].content, "Hello room")
  })

  it("failed bootstrap is not written to cache", () => {
    const key = roomBootstrapCacheKey({ userId: "u1", roomId: "r1" })
    writeRoomBootstrapCache(
      key,
      "u1",
      "r1",
      decodeRoomBootstrapV1(
        JSON.parse(JSON.stringify(roomContractFixtures.emptyRoom))
      ),
      "rpc"
    )
    clearRoomBootstrapCache("u1")
    assert.equal(readRoomBootstrapCache(key), null)
  })
})
export {}
