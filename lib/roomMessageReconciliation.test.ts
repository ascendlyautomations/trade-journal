import { describe, it, beforeEach } from "node:test"
import { RoomMessageReconciliationOwner, __roomMessageReconciliationTestOnlyReset, normalizeContentKey, } from "./roomMessageReconciliation.ts"
import assert from "node:assert/strict"

describe("roomMessageReconciliation", () => {
  beforeEach(() => {
    __roomMessageReconciliationTestOnlyReset()
  })

  it("POST before Realtime: skips hydration GET", async () => {
    const owner = new RoomMessageReconciliationOwner("u1")
    let hydrateCalls = 0

    const handle = owner.beginPendingSend({
      tempId: "temp-1",
      roomId: "r1",
      userId: "u1",
      sectionId: "s1",
      type: "text",
      contentKey: "text:hello",
    })

    const serverRow = {
      id: "m1",
      room_id: "r1",
      user_id: "u1",
      section_id: "s1",
      type: "text",
      content: "hello",
    }
    handle.complete(serverRow)

    const { result } = await owner.reconcileRealtimeInsert({
      messageId: "m1",
      partial: serverRow,
      roomId: "r1",
      viewerId: "u1",
      hydrate: async () => {
        hydrateCalls += 1
        return serverRow
      },
    })

    assert.equal(result, "skipped_confirmed")
    assert.equal(hydrateCalls, 0)
  })

  it("Realtime before POST: awaits local send without hydration GET", async () => {
    const owner = new RoomMessageReconciliationOwner("u1")
    let hydrateCalls = 0

    const handle = owner.beginPendingSend({
      tempId: "temp-2",
      roomId: "r1",
      userId: "u1",
      sectionId: null,
      type: "text",
      contentKey: "text:race",
    })

    const partial = {
      id: "m2",
      room_id: "r1",
      user_id: "u1",
      section_id: null,
      type: "text",
      content: "race",
    }

    const realtimeTask = owner.reconcileRealtimeInsert({
      messageId: "m2",
      partial,
      roomId: "r1",
      viewerId: "u1",
      hydrate: async () => {
        hydrateCalls += 1
        return partial
      },
    })

    await new Promise((r) => setTimeout(r, 5))
    assert.equal(hydrateCalls, 0)

    handle.complete(partial)
    const { result, row } = await realtimeTask
    assert.equal(result, "awaited_local_send")
    assert.equal(row?.id, "m2")
    assert.equal(hydrateCalls, 0)
  })

  it("unknown remote message: exactly one hydration GET (single-flight)", async () => {
    const owner = new RoomMessageReconciliationOwner("u1")
    let hydrateCalls = 0
    const remote = {
      id: "m3",
      room_id: "r1",
      user_id: "u2",
      type: "text",
      content: "remote",
    }

    const hydrate = async () => {
      hydrateCalls += 1
      await new Promise((r) => setTimeout(r, 10))
      return remote
    }

    const ctx = {
      messageId: "m3",
      partial: remote,
      roomId: "r1",
      viewerId: "u1",
      hydrate,
    }

    const [a, b] = await Promise.all([
      owner.reconcileRealtimeInsert(ctx),
      owner.reconcileRealtimeInsert(ctx),
    ])

    assert.equal(hydrateCalls, 1)
    assert.equal(a.result, "hydrated")
    assert.equal(b.result, "hydrated")
  })

  it("same user from another tab is not treated as local pending send", async () => {
    const owner = new RoomMessageReconciliationOwner("u1")
    let hydrateCalls = 0
    const remoteSameUser = {
      id: "m4",
      room_id: "r1",
      user_id: "u1",
      type: "text",
      content: "other-tab",
    }

    const { result } = await owner.reconcileRealtimeInsert({
      messageId: "m4",
      partial: remoteSameUser,
      roomId: "r1",
      viewerId: "u1",
      hydrate: async () => {
        hydrateCalls += 1
        return remoteSameUser
      },
    })

    assert.equal(result, "hydrated")
    assert.equal(hydrateCalls, 1)
  })

  it("content key distinguishes trade messages", () => {
    assert.equal(
      normalizeContentKey({ type: "trade", trade_id: "t1", content: "x" }),
      "trade:t1"
    )
  })

  it("reset clears viewer-scoped confirmed state", () => {
    const owner = new RoomMessageReconciliationOwner("u1")
    owner.markConfirmed("m9")
    owner.reset()
    assert.equal(owner.isConfirmedHydrated("m9"), false)
  })
})
export {}
