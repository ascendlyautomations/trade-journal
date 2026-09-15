import { describe, it } from "node:test"
import assert from "node:assert/strict"
import { brokerAccountFieldsAfterRediscovery } from "@/lib/integrations/brokerIntegrationAccounts"

describe("broker integration continuity", () => {
  it("restores linked mapping after disconnect marked inactive", () => {
    assert.deepEqual(
      brokerAccountFieldsAfterRediscovery({
        tradetraxs_account_id: "acct-1",
        status: "inactive",
      }),
      { status: "linked", syncEnabled: true }
    )
  })

  it("keeps discovered accounts unlinked after rediscovery", () => {
    assert.deepEqual(
      brokerAccountFieldsAfterRediscovery({
        tradetraxs_account_id: null,
        status: "inactive",
      }),
      { status: "discovered", syncEnabled: false }
    )
  })
})
