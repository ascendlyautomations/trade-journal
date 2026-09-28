import assert from "node:assert/strict"
import test from "node:test"
import { auditTradovateReferenceSep2026FillIds } from "./tradovateReferenceSep2026FillIds.ts"

test("reference Sep 2026 fill id audit", () => {
  const audit = auditTradovateReferenceSep2026FillIds()
  assert.equal(audit.uniqueFillIdCount, 36)
  assert.equal(audit.fixtureRowCount, 36)
  assert.equal(audit.fillIds.length, 36)
})
