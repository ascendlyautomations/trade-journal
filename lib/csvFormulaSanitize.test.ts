const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const { sanitizeCsvTextField } = require("./csvFormulaSanitize.ts")

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
