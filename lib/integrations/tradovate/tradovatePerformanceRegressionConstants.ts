/** Canonical Sep 2026 Performance regression — MGC fills missing in production before Phase 1. */
export const TRADOVATE_PERFORMANCE_MGC_RECOVERY_FILL_IDS = [
  "660290950326",
  "660290950296",
  "660290950290",
] as const

export const TRADOVATE_PERFORMANCE_EXPECTED = {
  completedLifecycles: 12,
  completedLifecyclesIncomplete: 11,
  mnqGross: -45,
  mgcGross: 5,
  mgcGrossIncomplete: -55,
  overallGross: -40,
  overallGrossIncomplete: -100,
  mgcRecoveryLifecycleGross: 60,
} as const
