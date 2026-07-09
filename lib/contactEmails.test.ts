import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  COPYRIGHT_EMAIL,
  NOTIFICATIONS_FROM_EMAIL,
  SUPPORT_EMAIL,
} from "./contactEmails"

describe("contactEmails", () => {
  it("uses the canonical support inbox", () => {
    assert.equal(SUPPORT_EMAIL, "support@tradetraxs.com")
  })

  it("keeps copyright on a separate mailbox", () => {
    assert.equal(COPYRIGHT_EMAIL, "copyright@tradetraxs.com")
  })

  it("uses notifications@ for outbound admin mail", () => {
    assert.match(NOTIFICATIONS_FROM_EMAIL, /notifications@tradetraxs\.com/)
  })
})
