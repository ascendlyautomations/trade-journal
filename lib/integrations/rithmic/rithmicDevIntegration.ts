/**
 * Rithmic user-facing broker UX and APIs are development-only until product launch.
 * - Local: `NODE_ENV=development` (e.g. `next dev`)
 * - Internal: `RITHMIC_DEV_INTEGRATION_ENABLED=1` on staging/debug hosts
 */
export function isRithmicDevelopmentIntegrationEnabled(): boolean {
  if (process.env.RITHMIC_DEV_INTEGRATION_ENABLED === "1") return true
  return process.env.NODE_ENV === "development"
}

export function rithmicDevelopmentIntegrationDisabledJson(): {
  error: string
  code: "development_only"
} {
  return {
    error: "Rithmic broker integration is only available in development environments.",
    code: "development_only",
  }
}

export function rithmicDevelopmentIntegrationDisabledResponse(
  status = 403
): Response {
  return Response.json(rithmicDevelopmentIntegrationDisabledJson(), { status })
}