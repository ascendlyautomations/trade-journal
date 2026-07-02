import type { DemoSignupReason } from "./DemoModeContext"

let demoSignupHandler: ((reason?: DemoSignupReason) => void) | null = null

export function registerDemoSignupHandler(
  handler: ((reason?: DemoSignupReason) => void) | null
): void {
  demoSignupHandler = handler
}

export function requestDemoSignup(reason: DemoSignupReason = "default"): void {
  demoSignupHandler?.(reason)
}
