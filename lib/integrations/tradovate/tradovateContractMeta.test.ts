import assert from "node:assert/strict"
import { describe, it } from "node:test"
import {
  mergeTradovateContractMetaMaps,
  mergeTradovateExecutionContractFields,
  resolveBrokerTradeTicker,
} from "./tradovateContractMeta.ts"
import { resolveEffectiveValuePerPoint } from "./futuresValuePerPointFallback.ts"
import { computeFuturesGrossPnl } from "./tradeReconstruction.ts"

describe("tradovateContractMeta", () => {
  it("uses execution symbol_root when REST contract map is empty", () => {
    const merged = mergeTradovateContractMetaMaps(
      new Map(),
      [
        {
          external_contract_id: "4399654",
          symbol_root: "MNQ",
          contract_name: "MNQU6",
        },
      ]
    )
    const meta = merged.get("4399654")
    assert.equal(meta?.symbolRoot, "MNQ")
    const ticker = resolveBrokerTradeTicker({
      contract: meta,
      contractId: "4399654",
    })
    assert.equal(ticker, "MNQ")
    const vpp = resolveEffectiveValuePerPoint({
      symbolRoot: ticker,
      contractValuePerPoint: null,
    })
    assert.equal(vpp, 2)
    const gross = computeFuturesGrossPnl("Short", 29011, 29000, 1, vpp!)
    assert.equal(gross, 22)
  })

  it("prefers non-numeric symbol_root over numeric contract id metadata", () => {
    const merged = mergeTradovateContractMetaMaps(
      new Map([
        [
          "4399654",
          {
            contractId: "4399654",
            contractName: "",
            symbolRoot: "4399654",
            valuePerPoint: null,
          },
        ],
      ]),
      [
        {
          external_contract_id: "4399654",
          symbol_root: "MNQ",
          contract_name: "MNQZ6",
        },
      ]
    )
    const ticker = resolveBrokerTradeTicker({
      contract: merged.get("4399654"),
      contractId: "4399654",
    })
    assert.equal(ticker, "MNQ")
  })

  it("mergeTradovateExecutionContractFields keeps MNQ over numeric REST symbol_root", () => {
    const merged = mergeTradovateExecutionContractFields(
      { symbol_root: "MNQ", contract_name: "MNQU6" },
      { symbol_root: "4399654", contract_name: "" }
    )
    assert.equal(merged.symbol_root, "MNQ")
  })

  it("normalizes contract names like MNQZ6 and MGCV6", () => {
    assert.equal(
      resolveBrokerTradeTicker({
        contract: { symbolRoot: "MNQZ6", contractName: "MNQZ6" },
        contractId: "4470324",
      }),
      "MNQ"
    )
    assert.equal(
      resolveBrokerTradeTicker({
        contract: { symbolRoot: "MGCV6", contractName: "MGCV6" },
        contractId: "4176766",
      }),
      "MGC"
    )
  })
})
