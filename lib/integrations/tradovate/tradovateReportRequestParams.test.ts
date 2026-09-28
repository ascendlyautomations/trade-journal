import assert from "node:assert/strict"
import test from "node:test"
import {
  buildTradovateDateRangeAccountReportParams,
  encodeTradovateAccountsReportParam,
  parseTradovateAccountEntityId,
} from "./tradovateReportRequestParams.ts"

test("parseTradovateAccountEntityId", () => {
  assert.equal(parseTradovateAccountEntityId("65788591"), 65788591)
  assert.equal(parseTradovateAccountEntityId(65788591), 65788591)
  assert.equal(parseTradovateAccountEntityId(""), null)
  assert.equal(parseTradovateAccountEntityId("abc"), null)
})

test("encodeTradovateAccountsReportParam uses JSON number", () => {
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
