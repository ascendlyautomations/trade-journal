import { isNativeIos } from "./nativePlatform"

/**
 * Capacitor Haptics for the iOS shell only.
 * Web, Android, and desktop are silent no-ops.
 */

type ImpactKind = "light" | "medium" | "heavy"
type NotifyKind = "success" | "warning" | "error"

const MIN_GAP_MS: Record<string, number> = {
  light: 40,
  medium: 80,
  heavy: 120,
  success: 200,
  warning: 150,
  error: 150,
}

const lastFiredAt = new Map<string, number>()

function shouldFire(key: string, gapMs: number): boolean {
  const now = Date.now()
  const prev = lastFiredAt.get(key) ?? 0
  if (now - prev < gapMs) return false
  lastFiredAt.set(key, now)
  return true
}

async function runHaptic(work: () => Promise<void>, key: string, gapMs: number) {
  if (typeof window === "undefined") return
  if (!isNativeIos()) return
  if (!shouldFire(key, gapMs)) return
  try {
    await work()
  } catch {
    // Plugin unavailable / simulator without haptics — ignore.
  }
}

export function hapticLight(bucket = "light") {
  void runHaptic(async () => {
    const { Haptics, ImpactStyle } = await import("@capacitor/haptics")
    await Haptics.impact({ style: ImpactStyle.Light })
  }, `impact:light:${bucket}`, MIN_GAP_MS.light)
}

export function hapticMedium(bucket = "medium") {
  void runHaptic(async () => {
    const { Haptics, ImpactStyle } = await import("@capacitor/haptics")
    await Haptics.impact({ style: ImpactStyle.Medium })
  }, `impact:medium:${bucket}`, MIN_GAP_MS.medium)
}

export function hapticHeavy(bucket = "heavy") {
  void runHaptic(async () => {
    const { Haptics, ImpactStyle } = await import("@capacitor/haptics")
    await Haptics.impact({ style: ImpactStyle.Heavy })
  }, `impact:heavy:${bucket}`, MIN_GAP_MS.heavy)
}

export function hapticSuccess(bucket = "success") {
  void runHaptic(async () => {
    const { Haptics, NotificationType } = await import("@capacitor/haptics")
    await Haptics.notification({ type: NotificationType.Success })
  }, `notify:success:${bucket}`, MIN_GAP_MS.success)
}

export function hapticWarning(bucket = "warning") {
  void runHaptic(async () => {
    const { Haptics, NotificationType } = await import("@capacitor/haptics")
    await Haptics.notification({ type: NotificationType.Warning })
  }, `notify:warning:${bucket}`, MIN_GAP_MS.warning)
}

export function hapticError(bucket = "error") {
  void runHaptic(async () => {
    const { Haptics, NotificationType } = await import("@capacitor/haptics")
    await Haptics.notification({ type: NotificationType.Error })
  }, `notify:error:${bucket}`, MIN_GAP_MS.error)
}

/** Map feedback popup types to the right haptic. */
export function hapticForFeedbackType(
  type: "success" | "error" | "warning" | "info" | undefined
) {
  if (type === "error") hapticError("feedback")
  else if (type === "warning") hapticWarning("feedback")
  else if (type === "success") hapticSuccess("feedback")
  // info: silent — too noisy for informational toasts
}

export type { ImpactKind, NotifyKind }
