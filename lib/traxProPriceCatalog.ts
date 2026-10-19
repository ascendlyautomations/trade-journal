import type { TraxProBillingIntervalId } from "./traxProBillingPlans.ts"

/** Public Stripe price presentation. Amounts come from Price objects, not the list-price formula. */

export type TraxProCatalogInterval = Exclude<TraxProBillingIntervalId, "test">

export type TraxProRecurringInterval = "day" | "week" | "month" | "year"

export type TraxProStripePriceInput = {
  interval: TraxProCatalogInterval
  unitAmountCents: number | null
  currency: string
  recurringInterval: TraxProRecurringInterval | null
  intervalCount: number | null
}

export type TraxProDisplayedPlan = {
  interval: TraxProCatalogInterval
  currency: string
  unitAmountCents: number
  totalLabel: string
  equivalentMonthlyLabel: string | null
  periodLabel: string
  billingCadenceLabel: string
  savePercent: number | null
  checkoutOptionLabel: string
  /** False when the Stripe recurring period is not the interval this price is configured for. */
  aligned: boolean
  monthsInCycle: number | null
}

export type TraxProPriceCatalog = {
  plans: TraxProDisplayedPlan[]
  trialDays: number | null
  unavailable: TraxProCatalogInterval[]
}

export type TraxProTrialPresentation = {
  offerSummary: string | null
  headline: string | null
  buttonTitle: string
  heroLine: string | null
  finePrint: string
}

const EXPECTED_MONTHS: Record<TraxProCatalogInterval, number> = {
  monthly: 1,
  six_month: 6,
  yearly: 12,
}

export function quoteFromStripePrice(
  interval: TraxProCatalogInterval,
  price: {
    unit_amount?: number | null
    currency?: string | null
    recurring?: { interval?: string | null; interval_count?: number | null } | null
  }
): TraxProStripePriceInput | null {
  const currency = price.currency?.trim().toLowerCase()
  const recurringInterval = normalizeRecurringInterval(price.recurring?.interval)
  if (!currency || !recurringInterval) return null
  const intervalCount = price.recurring?.interval_count
  return {
    interval,
    unitAmountCents:
      typeof price.unit_amount === "number" && Number.isFinite(price.unit_amount)
        ? price.unit_amount
        : null,
    currency,
    recurringInterval,
    intervalCount:
      typeof intervalCount === "number" && intervalCount > 0 ? intervalCount : null,
  }
}

export function presentTraxProStripePrices(
  prices: readonly TraxProStripePriceInput[],
  trial: { enabled: boolean; days: number }
): TraxProPriceCatalog {
  const displayed: TraxProDisplayedPlan[] = []
  for (const price of prices) {
    const plan = presentOne(price)
    if (plan) displayed.push(plan)
  }
  const monthly = displayed.find((plan) => plan.interval === "monthly" && plan.aligned)
  if (monthly) {
    for (const plan of displayed) {
      plan.savePercent = verifiedSavePercent(monthly, plan)
      plan.checkoutOptionLabel = checkoutLabel(plan)
    }
  }
  return {
    plans: displayed,
    trialDays: trial.enabled && trial.days > 0 ? Math.floor(trial.days) : null,
    unavailable: [],
  }
}

export function traxProTrialPresentation(
  trialDays: number | null
): TraxProTrialPresentation {
  if (trialDays == null || trialDays < 1) {
    return {
      offerSummary: null,
      headline: null,
      buttonTitle: "Upgrade to Pro",
      heroLine: null,
      finePrint: "Cancel anytime · Billed via Stripe",
    }
  }
  const days = Math.floor(trialDays)
  const period = days === 1 ? "1 day" : `${days} days`
  return {
    offerSummary: `${period} free trial`,
    headline: `${days}-Day Free Trial`,
    buttonTitle: `Start ${days}-Day Free Trial`,
    heroLine: `Try TraxPro free for ${days} ${days === 1 ? "day" : "days"}`,
    finePrint: `${period} free trial · Cancel anytime · Billed via Stripe`,
  }
}

export function traxProPostTrialFootnote(
  plan: Pick<TraxProDisplayedPlan, "totalLabel" | "billingCadenceLabel"> | null,
  trialDays: number | null
): string | null {
  if (trialDays == null || trialDays < 1 || !plan) return null
  return `Then ${plan.totalLabel}, ${plan.billingCadenceLabel.toLowerCase()}. Cancel anytime.`
}

export function publicTraxProPriceResponse(catalog: TraxProPriceCatalog) {
  return {
    ok: true as const,
    trialDays: catalog.trialDays,
    unavailable: catalog.unavailable,
    plans: catalog.plans.map((plan) => ({
      interval: plan.interval,
      currency: plan.currency,
      unitAmountCents: plan.unitAmountCents,
      totalLabel: plan.totalLabel,
      equivalentMonthlyLabel: plan.equivalentMonthlyLabel,
      periodLabel: plan.periodLabel,
      billingCadenceLabel: plan.billingCadenceLabel,
      savePercent: plan.savePercent,
      checkoutOptionLabel: plan.checkoutOptionLabel,
      aligned: plan.aligned,
      monthsInCycle: plan.monthsInCycle,
    })),
  }
}

function presentOne(price: TraxProStripePriceInput): TraxProDisplayedPlan | null {
  if (price.unitAmountCents == null || price.unitAmountCents < 0) return null
  if (!price.recurringInterval || !price.intervalCount) return null
  const monthsInCycle = monthsForRecurring(price.recurringInterval, price.intervalCount)
  const periodLabel = periodLabelFor(price.recurringInterval, price.intervalCount)
  const totalLabel = formatStripeUnitAmount(price.unitAmountCents, price.currency)
  const aligned =
    monthsInCycle != null && monthsInCycle === EXPECTED_MONTHS[price.interval]
  const equivalentMonthlyLabel =
    monthsInCycle != null
      ? `${formatStripeUnitAmount(
          Math.round(price.unitAmountCents / monthsInCycle),
          price.currency
        )}/mo`
      : null
  return {
    interval: price.interval,
    currency: price.currency,
    unitAmountCents: price.unitAmountCents,
    totalLabel,
    equivalentMonthlyLabel,
    periodLabel,
    billingCadenceLabel: cadenceLabel(price.recurringInterval, price.intervalCount),
    savePercent: null,
    checkoutOptionLabel: periodLabel,
    aligned,
    monthsInCycle,
  }
}

function verifiedSavePercent(
  monthly: TraxProDisplayedPlan,
  plan: TraxProDisplayedPlan
): number | null {
  if (
    !plan.aligned ||
    plan.interval === "monthly" ||
    plan.monthsInCycle == null ||
    plan.monthsInCycle <= 1
  ) {
    return null
  }
  if (monthly.currency !== plan.currency || monthly.unitAmountCents <= 0) return null
  const fullPrice = monthly.unitAmountCents * plan.monthsInCycle
  if (plan.unitAmountCents >= fullPrice) return null
  const percent = Math.round((1 - plan.unitAmountCents / fullPrice) * 100)
  return percent > 0 ? percent : null
}

function checkoutLabel(plan: TraxProDisplayedPlan): string {
  if (!plan.aligned) return plan.periodLabel
  if (plan.savePercent == null) return plan.periodLabel
  const star = plan.interval === "yearly" ? " ⭐" : ""
  return `${plan.periodLabel}${star}, Save ${plan.savePercent}%`
}

export function formatStripeUnitAmount(cents: number, currency: string): string {
  return new Intl.NumberFormat("en-US", {
    style: "currency",
    currency: currency.toUpperCase(),
  }).format(cents / 100)
}

function monthsForRecurring(
  interval: TraxProRecurringInterval,
  count: number
): number | null {
  if (interval === "month") return count
  if (interval === "year") return count * 12
  return null
}

function periodLabelFor(interval: TraxProRecurringInterval, count: number): string {
  if (interval === "month" && count === 1) return "Monthly"
  if (interval === "month") return `${count} months`
  if (interval === "year" && count === 1) return "Yearly"
  if (interval === "year") return `${count} years`
  if (interval === "week" && count === 1) return "Weekly"
  if (interval === "week") return `${count} weeks`
  if (interval === "day" && count === 1) return "Daily"
  return `${count} days`
}

function cadenceLabel(interval: TraxProRecurringInterval, count: number): string {
  if (interval === "month" && count === 1) return "Billed monthly"
  if (interval === "month") return `Billed every ${count} months`
  if (interval === "year" && count === 1) return "Billed yearly"
  if (interval === "year") return `Billed every ${count} years`
  return `Billed every ${periodLabelFor(interval, count).toLowerCase()}`
}

function normalizeRecurringInterval(value: string | null | undefined): TraxProRecurringInterval | null {
  if (value === "day" || value === "week" || value === "month" || value === "year") {
    return value
  }
  return null
}
