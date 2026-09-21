/**
 * Structural payload model for Dashboard V3 (pre/post payload-fix).
 * Run: node scripts/measure-dashboard-v3-payload-breakdown.mjs
 */

const PRESET_KEYS = ["d7", "d30", "d90", "ytd", "all"]

function estimateBundleBytes({ equityPoints = 11, distributionLabels = 60 }) {
  const metrics = 450
  const equity = equityPoints * 55 + 80
  const distributions = distributionLabels * 35 + 400
  const insights = 600
  return metrics + equity + distributions + insights
}

function estimateLegacyScopes(accountCount) {
  const scopes = 1 + accountCount
  const bundles = scopes * PRESET_KEYS.length
  const perBundle = estimateBundleBytes({})
  return {
    scopes,
    bundles,
    totalBytes: bundles * perBundle + 5000,
  }
}

function estimateCompactBootstrap(accountCount) {
  const aggregateBundles = PRESET_KEYS.length * estimateBundleBytes({})
  const metricsOnly = accountCount * PRESET_KEYS.length * 480
  const accounts = accountCount * 650
  return {
    aggregateBundles,
    accountMetrics: metricsOnly,
    accounts,
    totalBytes: aggregateBundles + metricsOnly + accounts + 2000,
  }
}

const accounts = 8
const legacy = estimateLegacyScopes(accounts)
const compact = estimateCompactBootstrap(accounts)

console.log("Dashboard V3 payload model (estimated serialized JSON bytes)")
console.log("Accounts:", accounts)
console.log("")
console.log("BEFORE (scopes × presets full bundles):")
console.log(JSON.stringify(legacy, null, 2))
console.log("")
console.log("AFTER (5 aggregate + account metrics-only matrix):")
console.log(JSON.stringify(compact, null, 2))
console.log("")
console.log(
  `Reduction factor (bootstrap only): ~${(legacy.totalBytes / compact.totalBytes).toFixed(1)}×`
)
