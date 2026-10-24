import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { describe, it } from "node:test"
import { buildPropFirmYearOverview, parseTaxReservePercent } from "./propFirmExpenseOverview.ts"
import { isPropFirmPayoutKey, normalizePropFirmAssignmentName } from "./propFirmPayoutAssignments.ts"
import {
  buildPropFirmTaxCsv,
  firmNameForPropPayout,
  propFirmNameForPayoutAccount,
  taxCustomPeriod,
  taxExportFilename,
} from "./propFirmExpenseTaxExport.ts"
import {
  accountPurchaseExpenseType,
  accountPurchaseIdentity,
  centsToDecimalString,
  decimalToCents,
  filterPropFirmExpenses,
  formatCents,
  parseMoneyToCents,
  summarizePropFirmExpenses,
  totalCostCents,
  validatePropFirmExpenseDraft,
  type PropFirmExpenseRecord,
} from "./propFirmExpenses.ts"

function expense(overrides: Partial<PropFirmExpenseRecord> = {}): PropFirmExpenseRecord {
  return {
    id: "1",
    userId: "user",
    propFirmName: "Apex",
    expenseType: "evaluation_purchase",
    costPerAccountCents: 1999,
    quantity: 3,
    totalCostCents: 5997,
    datePaid: "2026-10-01",
    paymentLabel: "Visa",
    notes: null,
    accountId: "acct",
    source: "manual",
    trackerKind: "prop_firm",
    projectLabel: null,
    customCategory: null,
    recurrence: null,
    seriesId: "1",
    ...overrides,
  }
}

describe("prop firm expense money", () => {
  it("parses and formats decimal cents without binary drift", () => {
    assert.equal(parseMoneyToCents("19.99"), 1999)
    assert.equal(parseMoneyToCents("$1,250.50"), 125050)
    assert.equal(parseMoneyToCents("10.1"), 1010)
    assert.equal(parseMoneyToCents("10.999"), null)
    assert.equal(totalCostCents(1999, 3), 5997)
    assert.equal(centsToDecimalString(5997), "59.97")
    assert.equal(formatCents(5997), "$59.97")
    assert.equal(formatCents(-250), "-$2.50")
    assert.equal(decimalToCents("150.00"), 15000)
  })
})

describe("prop firm expense analytics", () => {
  it("nets payouts against expenses and groups history", () => {
    const rows = [
      expense(),
      expense({
        id: "2",
        propFirmName: "apex",
        expenseType: "reset_fee",
        costPerAccountCents: 10000,
        quantity: 1,
        totalCostCents: 10000,
        datePaid: "2026-09-15",
      }),
    ]
    const summary = summarizePropFirmExpenses(rows, 25000, new Date(2026, 9, 23))
    assert.equal(summary.totalSpentCents, 15997)
    assert.equal(summary.totalAccountsPurchased, 4)
    assert.equal(summary.totalPayoutsCents, 25000)
    assert.equal(summary.netProfitCents, 9003)
    assert.equal(summary.byFirm.length, 1)
    assert.equal(summary.byFirm[0]?.totalCents, 15997)
    assert.deepEqual(
      summary.byCategory.map((row) => row.key),
      ["evaluation_purchase", "reset_fee"]
    )
    const october = summary.monthly.find((month) => month.monthKey === "2026-10")
    assert.equal(october?.totalCents, 5997)
    assert.equal(summary.monthly.length, 12)

    const filtered = filterPropFirmExpenses(rows, {
      firm: "apex",
      category: "reset_fee",
      from: "2026-09-01",
      to: "2026-09-30",
    })
    assert.equal(filtered.length, 1)
    assert.equal(filtered[0]?.id, "2")
  })

  it("maps eval and funded purchases and keeps one identity per account", () => {
    assert.equal(accountPurchaseExpenseType("Prop Firm", "Eval"), "evaluation_purchase")
    assert.equal(accountPurchaseExpenseType("Prop Firm", "Funded"), "activation_fee")
    assert.equal(accountPurchaseExpenseType("Personal", "Live"), null)
    assert.equal(accountPurchaseIdentity("abc"), accountPurchaseIdentity("abc"))
    assert.notEqual(accountPurchaseIdentity("abc"), accountPurchaseIdentity("def"))
  })

  it("rejects future dates and blank costs", () => {
    assert.match(
      validatePropFirmExpenseDraft(
        {
          propFirmName: "Apex",
          expenseType: "other",
          costDigits: "",
          quantityDigits: "1",
          datePaid: "2026-10-23",
          paymentLabel: "",
          notes: "",
          accountId: null,
        },
        { today: "2026-10-23" }
      ) ?? "",
      /cost/i
    )
    assert.match(
      validatePropFirmExpenseDraft(
        {
          propFirmName: "Apex",
          expenseType: "other",
          costDigits: "10",
          quantityDigits: "1",
          datePaid: "2026-10-24",
          paymentLabel: "",
          notes: "",
          accountId: null,
        },
        { today: "2026-10-23" }
      ) ?? "",
      /future/i
    )
  })
})

describe("prop firm expense tax csv", () => {
  it("keeps cents, escapes text, and totals only the selected period", () => {
    const csv = buildPropFirmTaxCsv({
      periodStart: "2026-01-01",
      periodEnd: "2026-12-31",
      expenses: [
        expense({
          propFirmName: "=Apex, Eval",
          paymentLabel: "Visa, personal",
          datePaid: "2026-02-01",
          costPerAccountCents: 1999,
          quantity: 3,
          totalCostCents: 5997,
        }),
        expense({
          id: "2",
          propFirmName: "Topstep",
          datePaid: "2025-12-31",
          totalCostCents: 10000,
        }),
      ],
      payouts: [
        { payoutDate: "2026-06-01", propFirmName: "Apex", amountCents: 25000 },
        { payoutDate: "2025-11-01", propFirmName: "Old", amountCents: 1000 },
      ],
    })
    assert.match(csv, /Total Recorded Expenses,59\.97/)
    assert.match(csv, /Total Recorded Payouts,250\.00/)
    assert.match(csv, /Net Payouts After Expenses,190\.03/)
    assert.match(csv, /Potentially Deductible Expenses \(unverified estimate\),59\.97/)
    assert.match(csv, /"'=Apex, Eval"/)
    assert.match(csv, /"Visa, personal"/)
    assert.match(csv, /19\.99,3,59\.97/)
    assert.equal(csv.includes("2025-12-31"), false)
    assert.equal(csv.includes("Topstep"), false)
    assert.match(csv, /does not determine tax treatment/)
    assert.equal(taxExportFilename("2026-01-01", "2026-12-31"), "tradetraxs-prop-firm-expenses-2026.csv")
    assert.equal(taxCustomPeriod("2026-03-02", "2026-03-01"), null)
    assert.equal(
      propFirmNameForPayoutAccount("acct", [
        expense({ source: "account_purchase", propFirmName: "Apex" }),
      ]),
      "Apex"
    )
    assert.equal(propFirmNameForPayoutAccount("missing", []), "Unassigned")
    assert.equal(
      propFirmNameForPayoutAccount("acct", [
        expense({ id: "a", propFirmName: "Apex", source: "manual" }),
        expense({ id: "b", propFirmName: "Topstep", source: "manual" }),
      ]),
      "Unassigned"
    )
  })
})

describe("prop firm year overview", () => {
  it("scopes the year, reserves only positive net, and leaves unmatched payouts unassigned", () => {
    const overview = buildPropFirmYearOverview({
      year: 2026,
      reservePercent: 25,
      expenses: [
        expense({
          datePaid: "2026-02-01",
          accountId: "acct",
          source: "account_purchase",
          propFirmName: "Apex",
          totalCostCents: 5997,
        }),
        expense({
          id: "old",
          datePaid: "2025-12-31",
          propFirmName: "Topstep",
          totalCostCents: 10000,
          accountId: null,
        }),
      ],
      payouts: [
        { payoutDate: "2026-06-01", accountId: "acct", amountCents: 25000 },
        { payoutDate: "2026-07-01", accountId: "other", amountCents: 10000 },
        { payoutDate: "2025-11-01", accountId: "acct", amountCents: 5000 },
      ],
    })
    assert.equal(overview.expenseCents, 5997)
    assert.equal(overview.payoutCents, 35000)
    assert.equal(overview.netCents, 29003)
    assert.equal(overview.deductibleEstimateCents, 5997)
    assert.equal(overview.reserveCents, 7251)
    assert.equal(overview.mostProfitableFirmKey, "apex")
    const apex = overview.firms.find((firm) => firm.key === "apex")
    assert.equal(apex?.payoutCents, 25000)
    assert.equal(apex?.shortfallCents, 0)
    const unassigned = overview.firms.find((firm) => firm.label === "Unassigned")
    assert.equal(unassigned?.payoutCents, 10000)
    assert.equal(unassigned?.spentCents, 0)
    assert.equal(overview.months.find((month) => month.monthKey === "2026-02")?.expenseCents, 5997)
    assert.equal(overview.months.find((month) => month.monthKey === "2026-06")?.payoutCents, 25000)
    assert.equal(overview.byCategory[0]?.label, "Evaluation")
    const assigned = buildPropFirmYearOverview({
      year: 2026,
      reservePercent: 25,
      expenses: [],
      payouts: [{
        payoutDate: "2026-04-01",
        accountId: "old-account",
        amountCents: 8000,
        assignedFirmName: "Apex",
      }],
    })
    assert.equal(assigned.firms[0]?.label, "Apex")
    assert.equal(assigned.firms.some((firm) => firm.label === "Unassigned"), false)
    const fromAccount = buildPropFirmYearOverview({
      year: 2026,
      reservePercent: 25,
      expenses: [
        expense({
          datePaid: "2026-02-01",
          propFirmName: "Alpha futures",
          totalCostCents: 6500,
          accountId: "alpha",
          source: "account_purchase",
        }),
      ],
      payouts: [{
        payoutDate: "2026-08-01",
        accountId: "funded",
        accountName: "Alpha futures 150K",
        amountCents: 95300,
      }],
    })
    const alpha = fromAccount.firms.find((firm) => firm.key === "alpha futures")
    assert.equal(alpha?.payoutCents, 95300)
    assert.equal(alpha?.spentCents, 6500)
    assert.equal(fromAccount.firms.some((firm) => firm.label === "Unassigned"), false)
    assert.equal(
      firmNameForPropPayout({
        accountId: "acct",
        expenses: [expense({ source: "account_purchase", propFirmName: "Apex" })],
        assignedFirmName: "Topstep",
      }),
      "Topstep"
    )
    assert.equal(normalizePropFirmAssignmentName("  Apex  "), "Apex")
    assert.equal(normalizePropFirmAssignmentName(""), null)
    assert.equal(isPropFirmPayoutKey("ledger:11111111-1111-1111-1111-111111111111"), true)
    assert.equal(isPropFirmPayoutKey("achievement:11111111-1111-1111-1111-111111111111"), true)
    assert.equal(isPropFirmPayoutKey("account:11111111-1111-1111-1111-111111111111"), false)
    assert.equal(parseTaxReservePercent("22.5"), 22.5)
    assert.equal(parseTaxReservePercent("0"), null)
    assert.equal(
      buildPropFirmYearOverview({
        year: 2026,
        reservePercent: 30,
        expenses: [expense({ totalCostCents: 20000, datePaid: "2026-01-02" })],
        payouts: [{ payoutDate: "2026-03-01", accountId: "acct", amountCents: 5000 }],
      }).reserveCents,
      0
    )
    const csv = buildPropFirmTaxCsv({
      periodStart: "2026-01-01",
      periodEnd: "2026-12-31",
      expenses: [expense({ datePaid: "2026-02-01", totalCostCents: 5997, costPerAccountCents: 5997, quantity: 1 })],
      payouts: [{ payoutDate: "2026-06-01", propFirmName: "Apex", amountCents: 25000 }],
      reservePercent: 25,
    })
    assert.match(csv, /Estimated Tax Reserve \(25% budgeting estimate\),47\.51/)
    assert.match(csv, /budgeting estimate, not a tax calculation/)
  })
})

describe("prop firm expense settings migration", () => {
  const sql = readFileSync(
    new URL("../supabase/migrations/20261023213000_prop_firm_expense_settings.sql", import.meta.url),
    "utf8"
  )

  it("stores one owner percentage and keeps it private", () => {
    assert.match(sql, /user_id uuid primary key references auth\.users \(id\) on delete cascade/)
    assert.match(sql, /tax_reserve_percent numeric\(5, 2\) not null/)
    assert.match(sql, /tax_reserve_percent > 0/)
    assert.match(sql, /user_id = \(select auth\.uid\(\)\)/)
    assert.match(sql, /enable row level security/)
    assert.match(sql, /grant select, insert, update on table public\.prop_firm_expense_settings to authenticated/)
  })
})

describe("prop firm payout assignment migration", () => {
  const sql = readFileSync(
    new URL("../supabase/migrations/20261024000520_prop_firm_payout_assignments.sql", import.meta.url),
    "utf8"
  )

  it("stores an owner firm label without changing payout records", () => {
    assert.match(sql, /primary key \(user_id, payout_key\)/)
    assert.match(sql, /payout_key ~ '\^\(ledger\|cycle\):/)
    assert.match(sql, /user_id = \(select auth\.uid\(\)\)/)
    assert.match(sql, /enable row level security/)
    assert.match(sql, /does not change the payout amount/)
    assert.doesNotMatch(sql, /account_payout_entries/)
    assert.doesNotMatch(sql, /account_payout_cycles/)
  })
})

describe("prop firm expense migration", () => {
  const sql = readFileSync(
    new URL("../supabase/migrations/20261023163000_prop_firm_expenses.sql", import.meta.url),
    "utf8"
  )

  it("keeps expense history when an account is deleted and blocks duplicate purchases", () => {
    assert.match(sql, /account_id uuid null references public\.accounts \(id\) on delete set null/)
    assert.doesNotMatch(sql, /references public\.accounts \(id\) on delete cascade/)
    assert.match(sql, /prop_firm_expenses_account_purchase_uidx/)
    assert.match(sql, /where source = 'account_purchase' and account_id is not null/)
    assert.match(sql, /enable row level security/)
    assert.match(sql, /user_id = \(select auth\.uid\(\)\)/)
    assert.match(sql, /generated always as \(round\(cost_per_account \* quantity, 2\)\) stored/)
    assert.match(sql, /security invoker/)
    assert.match(sql, /date_paid = excluded\.date_paid/)
  })
})
