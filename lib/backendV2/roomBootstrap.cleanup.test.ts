import { describe, it, beforeEach } from "node:test"
import { applyRoomBootstrapSectionSwitch, } from "./roomBootstrapApply.ts"
import { roomContractFixtures } from "./roomContractFixtures.ts"
import { decodeRoomBootstrapV1 } from "./roomContracts.ts"
import { shouldSkipLegacyRoomDataEffects, } from "./roomBootstrapCommunityLoad.ts"
import { __setBackendV2FlagForTests, __resetBackendV2FlagsForTests, } from "./flags.ts"
import assert from "node:assert/strict"
import type { SetStateAction } from "react"

describe("Phase F cleanup — legacy fan-out gates", () => {
  beforeEach(() => {
    __resetBackendV2FlagsForTests()
  })

  it("skips legacy room data effects when rooms flag is ON", () => {
    __setBackendV2FlagForTests("rooms", true)
    assert.equal(shouldSkipLegacyRoomDataEffects(), true)
  })

  it("allows legacy room data effects when rooms flag is OFF", () => {
    assert.equal(shouldSkipLegacyRoomDataEffects(), false)
  })
})

describe("Phase F cleanup — section switch apply", () => {
  it("updates only section message state", () => {
    const bootstrap = decodeRoomBootstrapV1(
      JSON.parse(JSON.stringify(roomContractFixtures.memberWithSections))
    )
    let sectionId: string | null = null
    let main: unknown[] = []
    let pinned: unknown[] = []
    let loading = true
    const cache: Record<string, unknown> = {}

    applyRoomBootstrapSectionSwitch(bootstrap, "r1", "u1", {
      setSections: () => {
        throw new Error("should not reset sections on section switch")
      },
      setSelectedSectionId: (id: SetStateAction<string | null>) => {
        sectionId = typeof id === "function" ? id(sectionId) : id
      },
      setPinnedMessages: (rows: SetStateAction<unknown[]>) => {
        pinned = typeof rows === "function" ? rows(pinned) : rows
      },
      setMessages: (rows: SetStateAction<unknown[]>) => {
        main = typeof rows === "function" ? rows(main) : rows
      },
      setHasOlderMessages: () => {},
      setLoadingMessages: (v: SetStateAction<boolean>) => {
        loading = typeof v === "function" ? v(loading) : v
      },
      setRoomNotificationsEnabled: () => {
        throw new Error("should not reset notification on section switch")
      },
      setChannelNotificationPrefs: () => {
        throw new Error("should not reset channel prefs on section switch")
      },
      setActiveMembers: () => {
        throw new Error("should not reset member stats on section switch")
      },
      setLeftMembers: () => {
        throw new Error("should not reset member stats on section switch")
      },
      setUnreadByRoomId: () => {
        throw new Error("should not patch unread on section switch")
      },
      patchRoomSectionsInSession: () => {},
      patchRoomMessagesInSession: (_uid, key, payload) => {
        cache[key] = payload
      },
      buildRoomMessagesCacheKey: () => "cache-key",
      messagesByRoomRef: { current: {} },
      setMessagesByRoom: () => {},
      markedReadRoomKeyRef: { current: null },
    })

    assert.ok(sectionId)
    assert.ok(main.length > 0)
    assert.equal(loading, false)
    assert.ok(cache["cache-key"])
    assert.equal(pinned.length, 0)
  })
})
export {}
