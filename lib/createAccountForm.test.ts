import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  ACCOUNT_VALUE_REQUIRED_MESSAGE,
  assertRequiredAccountValue,
} from "./createAccountForm.ts"

describe("assertRequiredAccountValue", () => {
  it("rejects empty and whitespace-only values", () => {
    assert.deepEqual(assertRequiredAccountValue(""), {
      ok: false,
      message: ACCOUNT_VALUE_REQUIRED_MESSAGE,
    })
    assert.deepEqual(assertRequiredAccountValue("   "), {
      ok: false,
      message: ACCOUNT_VALUE_REQUIRED_MESSAGE,
    })
    assert.deepEqual(assertRequiredAccountValue(null), {
      ok: false,
      message: ACCOUNT_VALUE_REQUIRED_MESSAGE,
    })
  })

  it("accepts formatted numeric account values", () => {
    assert.deepEqual(assertRequiredAccountValue("50,000"), {
      ok: true,
      value: "50000",
    })
    assert.deepEqual(assertRequiredAccountValue("$150000"), {
      ok: true,
      value: "150000",
    })
  })
})
