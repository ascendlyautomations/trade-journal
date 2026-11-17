import { describe, it } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"

const __dirname = path.dirname(fileURLToPath(import.meta.url))

import {
  linkedContentCaptionsEquivalent,
  shouldHideLinkedTradeDescription,
} from "./linkedContentCaptionDedup.ts"
describe("linkedContentCaptionDedup", () => {
  it("treats whitespace and line breaks as formatting-only", () => {
    assert.equal(
      linkedContentCaptionsEquivalent(
        "Line one\n\nLine two",
        "  Line one   Line two  "
      ),
      true
    )
  })

  it("keeps distinct captions visible", () => {
    assert.equal(
      linkedContentCaptionsEquivalent("Clip story", "Trade thesis"),
      false
    )
  })

  it("hides linked trade description when it repeats the clip caption", () => {
    assert.equal(
      shouldHideLinkedTradeDescription("Same text", {
        public_description: "Same text",
      }),
      true
    )
    assert.equal(
      shouldHideLinkedTradeDescription("Clip only", {
        notes: "Clip only",
      }),
      true
    )
    assert.equal(
      shouldHideLinkedTradeDescription("Clip", {
        public_description: "Different",
        notes: "Also different",
      }),
      false
    )
  })
})

describe("resolveReelCaption contract", () => {
  it("prefers stored reel caption before trade public_description", () => {
    const src = fs.readFileSync(path.join(__dirname, "reels.ts"), "utf8")
    assert.match(
      src,
      /const rawCaption = reel\.caption[\s\S]*if \(isTradeAttachedReel\(reel\)\)/
    )
  })
})

describe("hasResolvableLinkedTrade", () => {
  it("gates on trade join resolution, not trade_id alone", () => {
    const src = fs.readFileSync(path.join(__dirname, "reels.ts"), "utf8")
    assert.match(src, /export function hasResolvableLinkedTrade/)
    assert.match(src, /trade\.is_public === true/)
    assert.match(src, /viewer === owner/)
  })
})

describe("delete_own_trade preserves clips", () => {
  it("unlinks reels instead of deleting them", () => {
    const sql = fs.readFileSync(
      path.join(
        __dirname,
        "../supabase/migrations/20261112120000_reels_unlink_on_trade_delete.sql"
      ),
      "utf8"
    )
    assert.match(sql, /on delete set null/i)
    assert.match(sql, /update public\.reels[\s\S]*trade_id = null/)
    assert.doesNotMatch(sql, /delete from public\.reels where trade_id/)
  })
})
