export const BETA_WELCOME_SEEN_STORAGE_KEY = "tradetraxs_beta_welcome_seen_v1"

function scopedKey(userId: string): string {
  return `${BETA_WELCOME_SEEN_STORAGE_KEY}:${userId}`
}

export function readBetaWelcomeSeen(userId: string): boolean {
  if (typeof window === "undefined") return false
  try {
    return window.localStorage.getItem(scopedKey(userId)) === "1"
  } catch {
    return false
  }
}

export function writeBetaWelcomeSeen(userId: string) {
  if (typeof window === "undefined") return
  try {
    window.localStorage.setItem(scopedKey(userId), "1")
  } catch {
    /* ignore quota / private mode */
  }
}

export function shouldShowBetaWelcomeCard(options: {
  isBetaTester: boolean | null | undefined
  onboardingCompleted: boolean | null | undefined
  tradeCount: number
  welcomeSeen: boolean
}): boolean {
  if (options.isBetaTester !== true) return false
  if (options.onboardingCompleted !== true) return false
  if (options.tradeCount !== 0) return false
  if (options.welcomeSeen) return false
  return true
}
