import { describe, it } from "node:test"
import { shouldWarmAppDataCachesForPath, isPreAuthShellPath, } from "./appWarmPaths.ts"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"

import { fileURLToPath } from "node:url"
const __dirname = path.dirname(fileURLToPath(import.meta.url))

describe("Cold start — app warm path gating", () => {
  it("marketing and auth routes skip Dashboard warm", () => {
    assert.equal(shouldWarmAppDataCachesForPath("/"), false)
    assert.equal(shouldWarmAppDataCachesForPath("/pricing"), false)
    assert.equal(shouldWarmAppDataCachesForPath("/login"), false)
    assert.equal(shouldWarmAppDataCachesForPath("/privacy"), false)
    assert.equal(shouldWarmAppDataCachesForPath("/onboarding"), false)
  })

  it("app routes allow Dashboard warm", () => {
    assert.equal(shouldWarmAppDataCachesForPath("/dashboard"), true)
    assert.equal(shouldWarmAppDataCachesForPath("/feed"), true)
    assert.equal(shouldWarmAppDataCachesForPath("/trades"), true)
    assert.equal(shouldWarmAppDataCachesForPath("/settings"), true)
  })

  it("login is pre-auth shell", () => {
    assert.equal(isPreAuthShellPath("/login"), true)
    assert.equal(isPreAuthShellPath("/dashboard"), false)
  })
})

describe("Cold start — ownership wiring", () => {
  it("UserProfileProvider gates warmAppDataCaches by app warm path", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "UserProfileProvider.tsx"),
      "utf8"
    )
    assert.match(src, /shouldWarmAppDataCachesForPath/)
    assert.match(src, /authEvent === "SIGNED_IN"/)
  })

  it("UserProfileProvider uses one idempotent profile Realtime subscription", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "UserProfileProvider.tsx"),
      "utf8"
    )
    assert.match(src, /ensureProfileRealtimeSubscription/)
    assert.match(src, /profileRealtimeUserIdRef/)
    assert.doesNotMatch(src, /async function subscribeProfileRealtime/)
    const subscribeCalls = src.match(/ch\.subscribe\(\)/g) ?? []
    assert.equal(
      subscribeCalls.length,
      1,
      "expected exactly one profile channel subscribe()"
    )
  })

  it("dashboard defers copy trading until request or saved copy-group filter", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../app/(app)/dashboard/page.tsx"),
      "utf8"
    )
    assert.match(src, /copyGroupsRequested/)
    assert.match(src, /isCopyGroupFilterValue/)
    assert.match(src, /onRequestCopyGroups/)
    assert.doesNotMatch(src, /isPro && deferredSectionsReady/)
  })

  it("copy trading fetch uses nested select (single round trip)", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "copyTradingGroups.ts"),
      "utf8"
    )
    assert.match(src, /copy_trading_group_accounts/)
    assert.doesNotMatch(src, /\.in\("group_id", groupIds\)/)
  })

  it("trades defers copy trading until picker open or copy-group filter", () => {
    const src = fs.readFileSync(
      path.join(__dirname, "../app/(app)/trades/page.tsx"),
      "utf8"
    )
    assert.match(src, /copyGroupsRequested/)
    assert.match(src, /onAccountPickerOpen={requestCopyGroups}/)
    assert.doesNotMatch(src, /useCopyTradingGroups\(\s*user\?\.id,\s*isPro\s*\)/)
  })
})
export {}
