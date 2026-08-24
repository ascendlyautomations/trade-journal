;(function () {
  const assert = require("node:assert/strict")
  const fs = require("node:fs")
  const path = require("node:path")
  const { describe, it } = require("node:test")

  const INTRO_SRC = path.join(__dirname, "gettingStartedIntro.ts")

  function readIntroSource(): string {
    return fs.readFileSync(INTRO_SRC, "utf8")
  }

  describe("gettingStartedIntro popup persistence", () => {
    it("exports stable intro popup title constant", () => {
      const src = readIntroSource()
      assert.match(
        src,
        /GETTING_STARTED_INTRO_POPUP_TITLE = "Welcome to Getting Started"/
      )
    })

    it("markGettingStartedIntroSeen tries RPC before profile update fallback", () => {
      const src = readIntroSource()
      assert.match(src, /mark_getting_started_intro_seen/)
      assert.match(src, /\.from\("profiles"\)/)
      assert.match(src, /has_seen_getting_started_intro:\s*true/)
      assert.match(src, /rpcOk === true/)
    })

    it("markGettingStartedIntroSeen short-circuits in demo mode", () => {
      const src = readIntroSource()
      assert.match(src, /isDemoSupabaseBlocked\(\)/)
      assert.match(src, /if \(isDemoSupabaseBlocked\(\)\) return true/)
    })

    it("markGettingStartedIntroSeen returns false when persistence fails", () => {
      const src = readIntroSource()
      assert.match(src, /return ok/)
      assert.match(src, /console\.error\("markGettingStartedIntroSeen failed:"/)
    })

    it("does not use browser poster extraction or idle video loading", () => {
      const src = readIntroSource()
      assert.doesNotMatch(src, /<video/)
      assert.doesNotMatch(src, /captureReelPosterFromUrl/)
      assert.doesNotMatch(src, /getReelVideoFrameSource/)
    })
  })

  describe("gettingStartedIntro popup visibility contract", () => {
    it("intro popup never auto-shows", () => {
      const { shouldShowGettingStartedIntroPopup } = require("./gettingStartedChecklist.ts")
      assert.equal(
        shouldShowGettingStartedIntroPopup({
          onboardingCompleted: true,
          hasSeenGettingStartedIntro: false,
        }),
        false
      )
      assert.equal(
        shouldShowGettingStartedIntroPopup({
          onboardingCompleted: false,
          hasSeenGettingStartedIntro: false,
        }),
        false
      )
    })
  })
})()
