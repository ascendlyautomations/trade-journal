import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { setMobileWebTradeTitle } from "./mobileWebTradeTitle.ts"
import {
  isMobileWebMessageThreadPath,
  resolveMobileWebActiveTab,
  resolveMobileWebNavChrome,
  resolveMobileWebPageHeader,
  shouldHideMobileWebTabBar,
  shouldMountMobileWebTabBar,
  shouldUseMobileWebHistoryBack,
} from "./mobileWebTabBar.ts"

describe("resolveMobileWebActiveTab", () => {
  it("maps the five tab roots", () => {
    assert.equal(resolveMobileWebActiveTab("/dashboard", "/profile/ada"), "home")
    assert.equal(resolveMobileWebActiveTab("/feed", "/profile/ada"), "feed")
    assert.equal(resolveMobileWebActiveTab("/messages/abc", "/profile/ada"), "messages")
    assert.equal(resolveMobileWebActiveTab("/profile/ada", "/profile/ada"), "profile")
    assert.equal(resolveMobileWebActiveTab("/create/post", "/profile/ada"), "create")
    assert.equal(resolveMobileWebActiveTab("/app", "/profile/ada"), "create")
  })

  it("treats an open create sheet as the Create tab", () => {
    assert.equal(
      resolveMobileWebActiveTab("/feed", "/profile/ada", true),
      "create"
    )
  })

  it("leaves secondary destinations unselected", () => {
    assert.equal(resolveMobileWebActiveTab("/calendar", "/profile/ada"), null)
    assert.equal(resolveMobileWebActiveTab("/trades", "/profile/ada"), null)
    assert.equal(resolveMobileWebActiveTab("/explore", "/profile/ada"), null)
    assert.equal(resolveMobileWebActiveTab("/settings", "/profile/ada"), null)
  })
})

describe("shouldMountMobileWebTabBar", () => {
  it("is off on marketing home and signed-out sessions", () => {
    assert.equal(shouldMountMobileWebTabBar("/dashboard", false), false)
    assert.equal(shouldMountMobileWebTabBar("/", true), false)
    assert.equal(shouldMountMobileWebTabBar("/feed", true), true)
  })

  it("hides the tab bar on conversation threads, not the inbox", () => {
    assert.equal(shouldHideMobileWebTabBar("/messages"), false)
    assert.equal(shouldHideMobileWebTabBar("/messages/ada"), true)
    assert.equal(shouldMountMobileWebTabBar("/messages", true), true)
    assert.equal(shouldMountMobileWebTabBar("/messages/ada", true), false)
  })

  it("hides the tab bar on native-pushed rooms, payouts, and leaderboard", () => {
    assert.equal(shouldHideMobileWebTabBar("/community"), false)
    assert.equal(shouldHideMobileWebTabBar("/community", "?room=desk"), true)
    assert.equal(shouldHideMobileWebTabBar("/leaderboard"), true)
    assert.equal(shouldHideMobileWebTabBar("/withdrawals"), true)
    assert.equal(shouldHideMobileWebTabBar("/withdrawals/abc"), true)
  })

  it("hides the tab bar on native-pushed detail screens", () => {
    assert.equal(shouldHideMobileWebTabBar("/trade/abc"), true)
    assert.equal(shouldHideMobileWebTabBar("/trades"), false)
    assert.equal(shouldHideMobileWebTabBar("/post/xyz"), true)
    assert.equal(shouldHideMobileWebTabBar("/reel/clip-1"), true)
    assert.equal(shouldHideMobileWebTabBar("/backtest"), true)
    assert.equal(shouldHideMobileWebTabBar("/psychology/analytics"), true)
    assert.equal(shouldHideMobileWebTabBar("/psychology/coach"), true)
    assert.equal(shouldHideMobileWebTabBar("/check-in-history"), true)
    assert.equal(shouldHideMobileWebTabBar("/analytics/propfirm"), true)
    assert.equal(shouldHideMobileWebTabBar("/suggestions"), true)
    assert.equal(shouldHideMobileWebTabBar("/dashboard"), false)
    assert.equal(shouldHideMobileWebTabBar("/feed"), false)
    assert.equal(shouldHideMobileWebTabBar("/calendar"), false)
  })
})

describe("resolveMobileWebPageHeader", () => {
  it("uses native-style titles for secondary phone pages", () => {
    assert.deepEqual(resolveMobileWebPageHeader("/calendar"), {
      title: "Calendar",
      backHref: "/dashboard",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/explore"), {
      title: "Explore",
      backHref: "/feed",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/notifications"), {
      title: "Activity",
      backHref: "/dashboard",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/withdrawals"), {
      title: "Withdrawals",
      backHref: "/dashboard",
    })
    assert.equal(resolveMobileWebPageHeader("/dashboard"), null)
    assert.equal(resolveMobileWebPageHeader("/feed"), null)
    assert.deepEqual(resolveMobileWebPageHeader("/trade/abc"), {
      title: "Trade",
      backHref: "/trades",
    })
    setMobileWebTradeTitle("NQ")
    assert.deepEqual(resolveMobileWebPageHeader("/trade/abc"), {
      title: "NQ",
      backHref: "/trades",
    })
    setMobileWebTradeTitle(null)
    assert.deepEqual(resolveMobileWebPageHeader("/backtest"), {
      title: "Backtest Lab",
      backHref: "/dashboard",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/post/xyz"), {
      title: "Post",
      backHref: "/feed",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/psychology/analytics"), {
      title: "Psychology Analytics",
      backHref: "/dashboard",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/settings"), {
      title: "Settings",
      backHref: "/dashboard",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/leaderboard"), {
      title: "Leaderboards",
      backHref: "/explore",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/analyst"), {
      title: "AI Analyst",
      backHref: "/dashboard",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/community"), {
      title: "Trade Rooms",
      backHref: "/explore",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/community", "?room=desk"), {
      title: "Trade Room",
      backHref: "/community",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/analytics/propfirm"), {
      title: "Prop Firm",
      backHref: "/dashboard",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/psychology/coach"), {
      title: "Psychology Coach",
      backHref: "/psychology/analytics",
    })
    assert.deepEqual(resolveMobileWebPageHeader("/check-in-history/2026-10-30"), {
      title: "Check-In",
      backHref: "/check-in-history",
    })
  })
})

describe("resolveMobileWebNavChrome", () => {
  it("titles tab roots without a back control", () => {
    assert.deepEqual(resolveMobileWebNavChrome("/dashboard"), {
      title: "Dashboard",
      backHref: null,
      leading: "calendar",
      showBell: true,
      showCompose: false,
      showExplore: false,
    })
    assert.deepEqual(resolveMobileWebNavChrome("/feed"), {
      title: "Feed",
      backHref: null,
      leading: null,
      showBell: false,
      showCompose: false,
      showExplore: true,
    })
    assert.deepEqual(resolveMobileWebNavChrome("/messages"), {
      title: "Messages",
      backHref: null,
      leading: "settings",
      showBell: false,
      showCompose: true,
      showExplore: false,
    })
    assert.deepEqual(resolveMobileWebNavChrome("/profile/ada"), {
      title: "Profile",
      backHref: null,
      leading: null,
      showBell: false,
      showCompose: false,
      showExplore: false,
    })
  })

  it("uses back chrome on secondary pages without a duplicate Activity bell", () => {
    assert.equal(resolveMobileWebNavChrome("/calendar")?.leading, "back")
    assert.equal(resolveMobileWebNavChrome("/calendar")?.showBell, false)
    assert.equal(resolveMobileWebNavChrome("/analytics/propfirm")?.showBell, false)
    assert.equal(isMobileWebMessageThreadPath("/messages/ada"), true)
    assert.equal(resolveMobileWebNavChrome("/messages/ada"), null)
  })
})

describe("shouldUseMobileWebHistoryBack", () => {
  it("uses history only for same-origin in-app navigations", () => {
    assert.equal(
      shouldUseMobileWebHistoryBack(
        "http://localhost:3000/dashboard",
        "http://localhost:3000",
        3
      ),
      true
    )
    assert.equal(
      shouldUseMobileWebHistoryBack("", "http://localhost:3000", 2),
      false
    )
    assert.equal(
      shouldUseMobileWebHistoryBack(
        "https://example.com/",
        "http://localhost:3000",
        4
      ),
      false
    )
  })
})
