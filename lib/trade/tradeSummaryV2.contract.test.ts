import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  decodeProfileTabBootstrapV2,
  payloadUtf8Bytes,
  TRADE_SUMMARY_SCHEMA,
} from "./tradeSummaryV2Contract.ts"
import {
  compareProfileCardParity,
  PROFILE_SUMMARY_REMOVED_CATEGORIES,
} from "./tradeSummaryProfileParity.ts"

const profileTabV2Fixture = {
  meta: {
    contract_version: "v2" as const,
    found: true,
    server_time: "2026-09-21T20:00:00.000Z",
    viewer_id: "11111111-1111-1111-1111-111111111111",
  },
  data: {
    tab: "trades" as const,
    items: [
      {
        summary_schema: TRADE_SUMMARY_SCHEMA,
        id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
        user_id: "11111111-1111-1111-1111-111111111111",
        ticker: "MNQ",
        direction: "Long",
        pnl: 120,
        rr: 2.5,
        points: 22,
        contracts: 1,
        entry_time: "2026-08-11T14:32:00.000Z",
        exit_time: "2026-08-11T14:45:00.000Z",
        created_at: "2026-08-11T14:45:00.000Z",
        is_public: true,
        public_description: "Public caption",
        note_preview: "Held through the open drive.",
        image_url: "https://cdn.example/trade.png",
        image_display_mode: "contain",
        mode: "live",
        account_type: "live",
        trade_mode: null,
        duration_seconds: 780,
        duration_text: "13m",
      },
    ],
    engagement: {
      "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa": {
        like_count: 2,
        liked_by_me: true,
        comment_count: 1,
      },
    },
    next_cursor: null,
  },
}

describe("TradeSummary V2 contract decode", () => {
  it("decodes Profile tab V2 bootstrap", () => {
    const decoded = decodeProfileTabBootstrapV2(profileTabV2Fixture)
    assert.equal(decoded.meta.contract_version, "v2")
    assert.equal(decoded.data.items.length, 1)
    assert.equal(decoded.data.items[0]?.summary_schema, TRADE_SUMMARY_SCHEMA)
  })

  it("rejects wrong contract_version", () => {
    const bad = structuredClone(profileTabV2Fixture)
    bad.meta.contract_version = "v1" as "v2"
    assert.throws(() => decodeProfileTabBootstrapV2(bad), /v2/)
  })

  it("rejects missing summary_schema on items", () => {
    const bad = structuredClone(profileTabV2Fixture)
    ;(bad.data.items[0] as { summary_schema?: string }).summary_schema = "other"
    assert.throws(() => decodeProfileTabBootstrapV2(bad), /schema mismatch/)
  })

  it("handles locked / empty items", () => {
    const locked = {
      meta: {
        contract_version: "v2" as const,
        found: false,
        viewer_id: null,
      },
      data: {
        tab: "trades" as const,
        items: [],
        engagement: {},
        next_cursor: null,
      },
    }
    const decoded = decodeProfileTabBootstrapV2(locked)
    assert.equal(decoded.meta.found, false)
    assert.equal(decoded.data.items.length, 0)
  })
})

describe("Profile card parity (V1 row → V2 summary)", () => {
  const v1Row = {
    id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
    user_id: "11111111-1111-1111-1111-111111111111",
    ticker: "MNQ",
    direction: "Long",
    pnl: 120,
    rr: 2.5,
    points: 22,
    contracts: 1,
    notes: "Held through the open drive.",
    public_description: "Public caption",
    is_public: true,
    image_url: "https://cdn.example/trade.png",
    image_display_mode: "contain",
    mode: "live",
    account_type: "live",
    duration_seconds: 780,
    duration_text: "13m",
    confidence: 4,
    psychology_notes: "Should not compare",
    account_id: "secret-account",
    account_name: "My Funded",
  }

  it("owner viewer: note_preview matches notes prefix", () => {
    const v2Item = profileTabV2Fixture.data.items[0]!
    const diffs = compareProfileCardParity([v1Row], [v2Item], {
      isOwnerViewer: true,
    })
    assert.deepEqual(diffs, [])
  })

  it("public viewer: note_preview uses public_description not notes", () => {
    const v2Item = {
      ...profileTabV2Fixture.data.items[0]!,
      note_preview: "Public caption",
    }
    const diffs = compareProfileCardParity([v1Row], [v2Item], {
      isOwnerViewer: false,
    })
    assert.deepEqual(diffs, [])
  })

  it("documents removed field categories", () => {
    assert.ok(PROFILE_SUMMARY_REMOVED_CATEGORIES.includes("psychology"))
    assert.ok(PROFILE_SUMMARY_REMOVED_CATEGORIES.includes("account_identifiers"))
  })
})

describe("Payload size comparison (estimate)", () => {
  it("V2 summary page is smaller than synthetic V1 full row page", () => {
    const v1Page = Array.from({ length: 24 }, (_, i) => ({
      ...profileTabV2Fixture.data.items[0],
      id: `00000000-0000-0000-0000-${String(i).padStart(12, "0")}`,
      notes: "x".repeat(2000),
      psychology_notes: "y".repeat(500),
      import_source: "csv",
      account_id: "acct",
      account_name: "Hidden",
    }))
    const v2Page = profileTabV2Fixture.data.items
    const v1Bytes = payloadUtf8Bytes({ items: v1Page })
    const v2Bytes = payloadUtf8Bytes({ items: v2Page })
    assert.ok(v2Bytes < v1Bytes)
    const reduction = (1 - v2Bytes / v1Bytes) * 100
    assert.ok(reduction > 50, `expected >50% reduction, got ${reduction.toFixed(1)}%`)
  })
})
