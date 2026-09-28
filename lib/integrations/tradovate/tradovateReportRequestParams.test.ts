import assert from "node:assert/strict"
import test from "node:test"
import {
  buildPerformanceAccountEncodingVariants,
  buildTradovateDateRangeAccountReportParams,
  encodeTradovateAccountsReportParam,
  errorTextIndicatesAccountIdZero,
  parseTradovateAccountEntityId,
} from "./tradovateReportRequestParams.ts"

test("parseTradovateAccountEntityId", () => {
  assert.equal(parseTradovateAccountEntityId("65788591"), 65788591)
  assert.equal(parseTradovateAccountEntityId(65788591), 65788591)
  assert.equal(parseTradovateAccountEntityId(""), null)
  assert.equal(parseTradovateAccountEntityId("abc"), null)
})

test("encodeTradovateAccountsReportParam uses JSON number scalar", () => {
  const param = encodeTradovateAccountsReportParam("65788591")
  assert.equal(param.name, "account")
  assert.equal(param.value, 65788591)
  assert.equal(typeof param.value, "number")
})

test("buildTradovateDateRangeAccountReportParams", () => {
  const params = buildTradovateDateRangeAccountReportParams({
    startDate: "09/14/2026",
    endDate: "09/23/2026",
    accountEntityId: 65788591,
  })
  assert.deepEqual(params, [
    { name: "startDate", value: "09/14/2026" },
    { name: "endDate", value: "09/23/2026" },
    { name: "account", value: 65788591 },
  ])
})

test("buildPerformanceAccountEncodingVariants includes array shape", () => {
  const variants = buildPerformanceAccountEncodingVariants({
    startDate: "09/14/2026",
    endDate: "09/23/2026",
    accountEntityId: 65788591,
    accountName: "APEX4750210000003",
  })
  assert.ok(
    variants.some((v) => v.encodingName === "account_value_json_number_array")
  )
  const arrayVariant = variants.find(
    (v) => v.encodingName === "account_value_json_number_array"
  )
  assert.deepEqual(arrayVariant?.params[2]?.value, [65788591])
})

test("errorTextIndicatesAccountIdZero", () => {
  assert.equal(
    errorTextIndicatesAccountIdZero("account is not found (ID:0)"),
    true
  )
  assert.equal(errorTextIndicatesAccountIdZero("account is not found"), false)
})
