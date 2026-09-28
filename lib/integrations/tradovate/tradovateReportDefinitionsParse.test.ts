import assert from "node:assert/strict"
import test from "node:test"
import { extractReportDefinitionsFromResponse } from "./tradovateReportDefinitionsParse.ts"

test("extractReportDefinitionsFromResponse reads reports wrapper", () => {
  const defs = extractReportDefinitionsFromResponse({
    reports: [
      {
        name: "Performance",
        description: "Performance",
        params: [{ name: "startDate", paramType: "Date", optional: false }],
      },
      { name: "Orders", params: [] },
    ],
  })
  assert.deepEqual(defs.map((d) => d.name), ["Performance", "Orders"])
  assert.equal(defs[0]?.params[0]?.name, "startDate")
})

test("extractReportDefinitionsFromResponse accepts root array", () => {
  const defs = extractReportDefinitionsFromResponse([
    { name: "Cash History", params: [] },
  ])
  assert.equal(defs[0]?.name, "Cash History")
})
