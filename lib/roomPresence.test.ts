import { describe, it } from "node:test"
import assert from "node:assert/strict"
import {
  createRoomPresenceSession,
  deleteRoomPresence,
  fetchActiveRoomPresence,
  upsertRoomPresenceHeartbeat,
} from "./roomPresence.ts"
import type { SupabaseClient } from "@supabase/supabase-js"

type RoomPresenceQueryBuilder = {
  upsert(): Promise<{ error: null }>
  delete(): {
    eq(): {
      eq(): Promise<{ error: null }>
    }
  }
  select(): {
    eq(): {
      gt(): Promise<{ data: never[]; error: null }>
    }
  }
}

function createRoomPresenceSupabaseMock(
  onUpsert?: () => void,
  onDelete?: () => void,
  onSelect?: () => void
): SupabaseClient {
  const builder: RoomPresenceQueryBuilder = {
    upsert() {
      onUpsert?.()
      return Promise.resolve({ error: null })
    },
    delete() {
      onDelete?.()
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
      onSelect?.()
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

  const mock = {
    from(table: string) {
      assert.equal(table, "room_presence")
      return builder
    },
  }
  return mock as unknown as SupabaseClient
}

describe("roomPresence session lifecycle", () => {
  it("stop clears interval and deletes presence after in-flight heartbeat", async () => {
    let upsertCount = 0
    let deleteCount = 0
    const supabase = createRoomPresenceSupabaseMock(
      () => {
        upsertCount += 1
      },
      () => {
        deleteCount += 1
      }
    )

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
    const previousDocument = global.document
    const visibilityCallbacks: Array<() => void> = []
    let upsertCount = 0
    let selectCount = 0

    const fakeDocument = {
      visibilityState: "hidden" as DocumentVisibilityState,
      addEventListener(event: string, listener: EventListener) {
        if (event === "visibilitychange") {
          visibilityCallbacks.length = 0
          visibilityCallbacks.push(() => {
            listener(new Event("visibilitychange"))
          })
        }
      },
      removeEventListener(event: string, _listener: EventListener) {
        if (event === "visibilitychange") {
          visibilityCallbacks.length = 0
        }
      },
    }
    Object.defineProperty(global, "document", {
      configurable: true,
      value: fakeDocument,
    })

    const supabase = createRoomPresenceSupabaseMock(
      () => {
        upsertCount += 1
      },
      undefined,
      () => {
        selectCount += 1
      }
    )

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
      for (const callback of visibilityCallbacks) callback()
      await new Promise((resolve) => setTimeout(resolve, 0))
      assert.equal(upsertCount, 1)
      assert.equal(selectCount, 1)

      fakeDocument.visibilityState = "hidden"
      for (const callback of visibilityCallbacks) callback()
      await new Promise((resolve) => setTimeout(resolve, 25))
      assert.equal(upsertCount, 1)
      assert.equal(selectCount, 1)

      await session.stop()
      assert.equal(visibilityCallbacks.length, 0)
    } finally {
      Object.defineProperty(global, "document", {
        configurable: true,
        value: previousDocument,
      })
    }
  })
})
export {}
