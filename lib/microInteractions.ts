/**
 * Shared micro-interaction tokens for native-feeling UI feedback.
 * Durations stay in the 150–250ms range — no bounce/elastic.
 */

export const MICRO_MS = {
  instant: 120,
  fast: 180,
  standard: 220,
} as const

/** Tailwind / CSS class helpers (defined in globals.css). */
export const MICRO = {
  likePop: "tt-micro-like-pop",
  syncPulse: "tt-micro-sync-pulse",
  fadeIn: "tt-micro-fade-in",
  softEnter: "tt-micro-soft-enter",
  rollback: "tt-micro-rollback",
  statusSending: "tt-micro-status-sending",
  statusFailed: "tt-micro-status-failed",
  statusSent: "tt-micro-status-sent",
} as const
