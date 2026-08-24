import { describe, it } from "node:test"
import { sanitizeCsvTextField } from "./csvFormulaSanitize.ts"
import assert from "node:assert/strict"

describe("sanitizeCsvTextField", () => {
  it("prefixes formula-like values", () => {
    assert.equal(sanitizeCsvTextField("=1+1"), "'=1+1")
    assert.equal(sanitizeCsvTextField("+cmd"), "'+cmd")
    assert.equal(sanitizeCsvTextField("-2"), "'-2")
    assert.equal(sanitizeCsvTextField("@SUM(A1)"), "'@SUM(A1)")
  })

  it("leaves normal notes unchanged", () => {
    assert.equal(sanitizeCsvTextField("Good entry, held target"), "Good entry, held target")
  })
})
export {}
