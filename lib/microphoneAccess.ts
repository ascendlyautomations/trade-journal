import { devWarn } from "./devLog.ts"

export type MicrophoneAccessFailurePhase =
  | "idle"
  | "denied"
  | "unsupported"

export type MicrophoneAccessFailure = {
  phase: MicrophoneAccessFailurePhase
  message: string
}

export function isSecureRecordingContext(): boolean {
  if (typeof window === "undefined") return false
  return window.isSecureContext === true
}

export function hasGetUserMediaSupport(): boolean {
  return (
    typeof navigator !== "undefined" &&
    typeof navigator.mediaDevices?.getUserMedia === "function"
  )
}

function errorName(error: unknown): string {
  if (error && typeof error === "object" && "name" in error) {
    return String((error as { name?: unknown }).name ?? "")
  }
  return ""
}

function errorMessage(error: unknown): string {
  if (error && typeof error === "object" && "message" in error) {
    return String((error as { message?: unknown }).message ?? "")
  }
  if (error instanceof Error) return error.message
  return String(error ?? "")
}

export function logMicrophoneAccessError(
  context: string,
  error: unknown
): void {
  devWarn(`[microphoneAccess] ${context}`, {
    name: errorName(error),
    message: errorMessage(error),
    error,
  })
}

/** Map getUserMedia failures to user-facing copy (call after preflight checks). */
export function describeMicrophoneAccessFailure(
  error: unknown
): MicrophoneAccessFailure {
  const name = errorName(error)
  const message = errorMessage(error).toLowerCase()

  if (name === "NotAllowedError" || name === "PermissionDeniedError") {
    return {
      phase: "denied",
      message:
        "Microphone access is blocked. Allow microphone access for TradeTraxs in your browser settings, then try again.",
    }
  }

  if (name === "NotFoundError" || name === "DevicesNotFoundError") {
    return {
      phase: "unsupported",
      message: "No microphone was found. Connect a microphone and try again.",
    }
  }

  if (
    name === "NotReadableError" ||
    name === "TrackStartError" ||
    message.includes("could not start") ||
    message.includes("device in use")
  ) {
    return {
      phase: "unsupported",
      message:
        "Your microphone is unavailable or already in use by another app. Close other apps using the mic and try again.",
    }
  }

  if (name === "OverconstrainedError" || name === "ConstraintNotSatisfiedError") {
    return {
      phase: "unsupported",
      message: "This microphone does not support the required audio settings.",
    }
  }

  if (name === "SecurityError") {
    return {
      phase: "unsupported",
      message:
        "Microphone access is blocked by browser security settings. Use HTTPS and allow microphone access for this site.",
    }
  }

  if (name === "AbortError") {
    return {
      phase: "idle",
      message: "Recording was interrupted. Please try again.",
    }
  }

  return {
    phase: "unsupported",
    message: "Could not start recording. Please try again.",
  }
}

export function describeRecordingSetupFailure(error: unknown): string {
  logMicrophoneAccessError("recording setup failed after mic granted", error)
  const name = errorName(error)
  if (name === "NotSupportedError") {
    return "Voice recording is not supported in this browser."
  }
  return "Recording failed to start. Please try again."
}
