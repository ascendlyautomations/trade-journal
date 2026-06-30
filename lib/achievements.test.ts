const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  ACHIEVEMENT_TYPE,
  achievementMatchesCategoryFilter,
  achievementTypeLabel,
  canonicalAchievementType,
  categoryFromType,
  isPayoutAchievementType,
  isPropFirmPayoutAchievementType,
  sumPayoutAchievementTotals,
} = require("./achievementTypes.ts")

describe("achievement payout types", () => {
  it("labels prop firm and live trading payouts separately", () => {
    assert.equal(
      achievementTypeLabel(ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT),
      "Prop Firm Payout"
    )
    assert.equal(
      achievementTypeLabel(ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT),
      "Live Trading Payout"
    )
  })

  it("maps legacy payout to live trading on read", () => {
    assert.equal(
      canonicalAchievementType("payout"),
      ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT
    )
  })

  it("keeps prop firm payout distinct from live trading", () => {
    assert.equal(
      canonicalAchievementType("prop_firm_payout"),
      ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT
    )
    assert.equal(isPropFirmPayoutAchievementType("prop_firm_payout"), true)
    assert.equal(isPropFirmPayoutAchievementType("live_trading_payout"), false)
  })

  it("assigns categories for future filtering", () => {
    assert.equal(
      categoryFromType(ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT),
      "prop_firm_payouts"
    )
    assert.equal(
      categoryFromType(ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT),
      "live_trading_payouts"
    )
  })

  it("includes both payout types in the payouts filter bucket", () => {
    assert.equal(
      achievementMatchesCategoryFilter(
        {
          achievement_type: ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT,
          category: "prop_firm_payouts",
        },
        "payouts"
      ),
      true
    )
    assert.equal(
      achievementMatchesCategoryFilter(
        {
          achievement_type: ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT,
          category: "live_trading_payouts",
        },
        "payouts"
      ),
      true
    )
    assert.equal(
      achievementMatchesCategoryFilter(
        { achievement_type: "payout", category: "payouts" },
        "payouts"
      ),
      true
    )
  })

  it("sums both payout achievement types for profile totals", () => {
    const total = sumPayoutAchievementTotals([
      {
        achievement_type: ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT,
        value_numeric: 1500,
      },
      {
        achievement_type: ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT,
        value_numeric: 500,
      },
      { achievement_type: ACHIEVEMENT_TYPE.MILESTONE, value_numeric: 999 },
    ])
    assert.equal(total, 2000)
    assert.equal(isPayoutAchievementType(ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT), true)
    assert.equal(isPayoutAchievementType(ACHIEVEMENT_TYPE.MILESTONE), false)
  })
})

describe("achievement track filters", () => {
  const {
    achievementMatchesTrackFilter,
    achievementTrackFromType,
  } = require("./achievementTypes.ts")

  it("assigns prop firm types to the prop firm track", () => {
    assert.equal(
      achievementTrackFromType(ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT),
      "prop_firm"
    )
    assert.equal(
      achievementTrackFromType(ACHIEVEMENT_TYPE.PASSED_EVAL),
      "prop_firm"
    )
    assert.equal(
      achievementTrackFromType("prop_firm_funded"),
      "prop_firm"
    )
  })

  it("assigns live trading types to the live trading track", () => {
    assert.equal(
      achievementTrackFromType(ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT),
      "live_trading"
    )
    assert.equal(
      achievementTrackFromType("live_trading_milestone"),
      "live_trading"
    )
  })

  it("keeps general milestones in the general track", () => {
    assert.equal(achievementTrackFromType(ACHIEVEMENT_TYPE.MILESTONE), "general")
  })

  it("filters achievements by track on the client", () => {
    const propFirmPayout = {
      achievement_type: ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT,
    }
    const passedEval = { achievement_type: ACHIEVEMENT_TYPE.PASSED_EVAL }
    const livePayout = {
      achievement_type: ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT,
    }
    const milestone = { achievement_type: ACHIEVEMENT_TYPE.MILESTONE }

    assert.equal(achievementMatchesTrackFilter(propFirmPayout, "all"), true)
    assert.equal(achievementMatchesTrackFilter(milestone, "all"), true)

    assert.equal(achievementMatchesTrackFilter(propFirmPayout, "prop_firm"), true)
    assert.equal(achievementMatchesTrackFilter(passedEval, "prop_firm"), true)
    assert.equal(achievementMatchesTrackFilter(livePayout, "prop_firm"), false)
    assert.equal(achievementMatchesTrackFilter(milestone, "prop_firm"), false)

    assert.equal(achievementMatchesTrackFilter(livePayout, "live_trading"), true)
    assert.equal(achievementMatchesTrackFilter(propFirmPayout, "live_trading"), false)
    assert.equal(achievementMatchesTrackFilter(milestone, "live_trading"), false)
  })
})

describe("achievement type filters", () => {
  const { achievementMatchesTypeFilter } = require("./achievementTypes.ts")

  it("filters by individual achievement types", () => {
    const propFirmPayout = {
      achievement_type: ACHIEVEMENT_TYPE.PROP_FIRM_PAYOUT,
      category: "prop_firm_payouts",
    }
    const livePayout = {
      achievement_type: ACHIEVEMENT_TYPE.LIVE_TRADING_PAYOUT,
      category: "live_trading_payouts",
    }
    const legacyPayout = {
      achievement_type: "payout",
      category: "payouts",
    }
    const passedEval = {
      achievement_type: ACHIEVEMENT_TYPE.PASSED_EVAL,
      category: "passed_evals",
    }
    const milestone = {
      achievement_type: ACHIEVEMENT_TYPE.MILESTONE,
      category: "milestones",
    }

    assert.equal(achievementMatchesTypeFilter(propFirmPayout, "all"), true)
    assert.equal(achievementMatchesTypeFilter(propFirmPayout, "prop_firm_payout"), true)
    assert.equal(achievementMatchesTypeFilter(propFirmPayout, "live_trading_payout"), false)

    assert.equal(achievementMatchesTypeFilter(livePayout, "live_trading_payout"), true)
    assert.equal(achievementMatchesTypeFilter(legacyPayout, "live_trading_payout"), true)

    assert.equal(achievementMatchesTypeFilter(passedEval, "passed_evals"), true)
    assert.equal(achievementMatchesTypeFilter(milestone, "milestones"), true)
    assert.equal(achievementMatchesTypeFilter(milestone, "prop_firm_payout"), false)
  })
})
