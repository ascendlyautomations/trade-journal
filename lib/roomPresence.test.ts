const assert = require("node:assert/strict")
const { describe, it } = require("node:test")

describe("roomPresence session lifecycle", () => {
  it("stop clears interval and deletes presence after in-flight heartbeat", async () => {
    const {
      createRoomPresenceSession,
      upsertRoomPresenceHeartbeat,
      deleteRoomPresence,
      fetchActiveRoomPresence,
    } = require("./roomPresence.ts")

    let upsertCount = 0
    let deleteCount = 0
    const supabase = {
      from(table: string) {
        assert.equal(table, "room_presence")
        return {
          upsert() {
            upsertCount += 1
            return Promise.resolve({ error: null })
          },
          delete() {
            deleteCount += 1
            return {
              eq() {
                return {
                  eq() {
                    return Promise.resolve({ error: null })
                  },
                }
              },
            }
          },
          select() {
            return {
              eq() {
                return {
                  gt() {
                    return Promise.resolve({ data: [], error: null })
                  },
                }
              },
            }
          },
        }
      },
    }

    const session = createRoomPresenceSession(supabase, {
      roomId: "room-1",
      userId: "user-1",
      onActiveUsers: () => {},
      heartbeatMs: 60_000,
    })

    await new Promise((r) => setTimeout(r, 0))
    assert.equal(upsertCount, 1)

    await session.stop()
    assert.equal(deleteCount, 1)

    upsertCount = 0
    await upsertRoomPresenceHeartbeat(supabase, "room-1", "user-1")
    assert.equal(upsertCount, 1)

    deleteCount = 0
    await deleteRoomPresence(supabase, "room-1", "user-1")
    assert.equal(deleteCount, 1)

    const users = await fetchActiveRoomPresence(supabase, "room-1")
    assert.deepEqual(users, [])
  })

  it("pauses while hidden and refreshes immediately when visible", async () => {
    const { createRoomPresenceSession } = require("./roomPresence.ts")
    const previousDocument = global.document
    let visibilityListener: (() => void) | null = null
    let upsertCount = 0
    let selectCount = 0

    const fakeDocument = {
      visibilityState: "hidden",
      addEventListener(event: string, listener: () => void) {
        if (event === "visibilitychange") visibilityListener = listener
      },
      removeEventListener(event: string, listener: () => void) {
        if (event === "visibilitychange" && visibilityListener === listener) {
          visibilityListener = null
        }
      },
    }
    Object.defineProperty(global, "document", {
      configurable: true,
      value: fakeDocument,
    })

    const supabase = {
      from() {
        return {
          upsert() {
            upsertCount += 1
            return Promise.resolve({ error: null })
          },
          delete() {
            return {
              eq() {
                return {
                  eq() {
                    return Promise.resolve({ error: null })
                  },
                }
              },
            }
          },
          select() {
            selectCount += 1
            return {
              eq() {
                return {
                  gt() {
                    return Promise.resolve({ data: [], error: null })
                  },
                }
              },
            }
          },
        }
      },
    }

    try {
      const session = createRoomPresenceSession(supabase, {
        roomId: "room-1",
        userId: "user-1",
        onActiveUsers: () => {},
        heartbeatMs: 10,
      })

      await new Promise((resolve) => setTimeout(resolve, 25))
      assert.equal(upsertCount, 0)
      assert.equal(selectCount, 0)

      fakeDocument.visibilityState = "visible"
      visibilityListener?.()
      await new Promise((resolve) => setTimeout(resolve, 0))
      assert.equal(upsertCount, 1)
      assert.equal(selectCount, 1)

      fakeDocument.visibilityState = "hidden"
      visibilityListener?.()
      await new Promise((resolve) => setTimeout(resolve, 25))
      assert.equal(upsertCount, 1)
      assert.equal(selectCount, 1)

      await session.stop()
      assert.equal(visibilityListener, null)
    } finally {
      Object.defineProperty(global, "document", {
        configurable: true,
        value: previousDocument,
      })
    }
  })
})
