import { describe, it, beforeEach } from "node:test"
import { writeSessionBootstrapCache, clearSessionBootstrapCache, readSessionBootstrapCache, getSessionBadges, patchSessionBadges, getSessionIsAdmin, } from "./sessionBootstrapCache.ts"
import { sessionBootstrapFixture } from "./fixtures.ts"
import { __resetBackendV2FlagsForTests } from "./flags.ts"
import assert from "node:assert/strict"

describe("Backend V2 session cache ownership", () => {
  beforeEach(() => {
    clearSessionBootstrapCache()
    __resetBackendV2FlagsForTests()
  })

  it("stores one bootstrap per user and patches badges without new documents", () => {
    const uid = sessionBootstrapFixture.meta.viewer_id
    assert.ok(uid)
    writeSessionBootstrapCache(uid, sessionBootstrapFixture, "rpc")
    assert.equal(readSessionBootstrapCache(uid)?.data.badges.dm_unread, 1)
    patchSessionBadges(uid, { dm_unread: 9, notifications_unread: 4 })
    const badges = getSessionBadges(uid)
    assert.equal(badges?.dm_unread, 9)
    assert.equal(badges?.notifications_unread, 4)
  })

  it("exposes is_admin from entitlement flags", () => {
    const uid = sessionBootstrapFixture.meta.viewer_id
    assert.ok(uid)
    const withAdmin = JSON.parse(JSON.stringify(sessionBootstrapFixture))
    withAdmin.data.viewer.entitlement.flags.is_admin = true
    writeSessionBootstrapCache(uid, withAdmin, "rpc")
    assert.equal(getSessionIsAdmin(uid), true)
  })
})
export {}
