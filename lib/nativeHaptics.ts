import { isNativeIos } from "./nativePlatform"

/**
 * Haptic helpers — no-ops after Capacitor removal.
 * Call sites remain; Swift owns haptics in `native-ios/`.
 */

type ImpactKind = "light" | "medium" | "heavy"
type NotifyKind = "success" | "warning" | "error"

export function hapticLight(_bucket = "light") {
  if (!isNativeIos()) return
}

export function hapticMedium(_bucket = "medium") {
  if (!isNativeIos()) return
}

export function hapticHeavy(_bucket = "heavy") {
  if (!isNativeIos()) return
}

export function hapticSuccess(_bucket = "success") {
  if (!isNativeIos()) return
}

export function hapticWarning(_bucket = "warning") {
  if (!isNativeIos()) return
}

export function hapticError(_bucket = "error") {
  if (!isNativeIos()) return
}

export function hapticForFeedbackType(
  type: "success" | "error" | "warning" | "info" | undefined
) {
  if (type === "error") hapticError("feedback")
  else if (type === "warning") hapticWarning("feedback")
  else if (type === "success") hapticSuccess("feedback")
}

export type { ImpactKind, NotifyKind }
