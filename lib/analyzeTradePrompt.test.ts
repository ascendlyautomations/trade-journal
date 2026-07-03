const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  ANALYZE_TRADE_SYSTEM_PROMPT,
  buildAnalyzeTradeHistoryContext,
  buildTradeAnalysisPrompt,
  formatTradeDataSection,
} = require("./analyzeTradePrompt.ts")

describe("formatTradeDataSection", () => {
  it("includes only populated fields", () => {
    const section = formatTradeDataSection({
      ticker: "NQ",
      direction: "Long",
      pnl: 420,
      rr: 2.1,
      notes: "",
      mistakes: null,
    })

    assert.match(section, /Symbol: NQ/)
    assert.match(section, /Direction: Long/)
    assert.match(section, /P&L: 420/)
    assert.match(section, /RR: 2.1/)
    assert.doesNotMatch(section, /Notes:/)
    assert.doesNotMatch(section, /Mistakes:/)
    assert.doesNotMatch(section, /None provided/)
  })
})

describe("buildAnalyzeTradeHistoryContext", () => {
  it("summarizes prior trade performance", () => {
    const trades = [
      { id: "current", ticker: "NQ", pnl: 100, rr: 2, session: "NY" },
      { id: "1", ticker: "NQ", pnl: 200, rr: 2.5, session: "NY" },
      { id: "2", ticker: "ES", pnl: -100, rr: 0.8, session: "NY" },
      { id: "3", ticker: "NQ", pnl: 150, rr: 1.8, session: "NY" },
      { id: "4", ticker: "NQ", pnl: -50, rr: 0.6, session: "London" },
    ]

    const ctx = buildAnalyzeTradeHistoryContext(trades, "current")
    assert.ok(ctx)
    assert.match(ctx.summaryText, /Sample size: 4/)
    assert.match(ctx.summaryText, /Historical win rate/)
    assert.match(ctx.summaryText, /Historical average RR/)
    assert.match(ctx.summaryText, /NQ history/)
  })

  it("returns null when no prior trades exist", () => {
    assert.equal(
      buildAnalyzeTradeHistoryContext([{ id: "only", pnl: 10 }], "only"),
      null
    )
  })
})

describe("buildTradeAnalysisPrompt", () => {
  it("uses coaching instructions and new headings guidance", () => {
    const prompt = buildTradeAnalysisPrompt(
      { id: "t1", ticker: "ES", pnl: -120, rr: 0.7, direction: "Short" },
      null,
      { hasScreenshot: false }
    )

    assert.match(prompt, /experienced coach/i)
    assert.match(prompt, /Coaching priorities/)
    assert.match(prompt, /Follow the markdown heading format/)
  })

  it("includes history block when available", () => {
    const prompt = buildTradeAnalysisPrompt(
      { id: "t1", ticker: "NQ", pnl: 100 },
      { summaryText: "Historical win rate: 55.0%" },
      { hasScreenshot: true }
    )

    assert.match(prompt, /Historical win rate: 55.0%/)
    assert.match(prompt, /chart screenshot/i)
  })
})

describe("ANALYZE_TRADE_SYSTEM_PROMPT", () => {
  it("defines mentor tone and output sections", () => {
    assert.match(ANALYZE_TRADE_SYSTEM_PROMPT, /experienced trading coach/)
    assert.match(ANALYZE_TRADE_SYSTEM_PROMPT, /## Summary/)
    assert.match(ANALYZE_TRADE_SYSTEM_PROMPT, /## Strengths/)
    assert.match(
      ANALYZE_TRADE_SYSTEM_PROMPT,
      /## Questions That Could Improve Future Analysis/
    )
    assert.match(
      ANALYZE_TRADE_SYSTEM_PROMPT,
      /Do NOT tell the trader to "journal more"/
    )
  })
})
