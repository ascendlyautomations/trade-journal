/**
 * Development-only Backend V2 RPC instrumentation.
 * No analytics service — console logging when enabled.
 */

export type BackendV2TelemetryEvent = {
  rpcName: string
  success: boolean
  executionMs: number
  decodeMs: number | null
  payloadBytes: number | null
  cacheHit: boolean | null
  cacheMiss: boolean | null
  errorCode: string | null
  flagName: string | null
}

export type BackendV2TelemetrySink = (event: BackendV2TelemetryEvent) => void

let sink: BackendV2TelemetrySink | null = null
let enabled =
  typeof process !== "undefined" && process.env.NODE_ENV === "development"

export function setBackendV2TelemetryEnabled(value: boolean): void {
  enabled = value
}

export function setBackendV2TelemetrySink(next: BackendV2TelemetrySink | null): void {
  sink = next
}

export function recordBackendV2Telemetry(event: BackendV2TelemetryEvent): void {
  if (!enabled) return
  if (sink) {
    sink(event)
    return
  }
  const status = event.success ? "ok" : "fail"
  const cache =
    event.cacheHit === true
      ? "hit"
      : event.cacheMiss === true
        ? "miss"
        : "n/a"
  // eslint-disable-next-line no-console
  console.debug(
    `[backendV2] ${event.rpcName} ${status} exec=${event.executionMs.toFixed(1)}ms decode=${event.decodeMs?.toFixed(1) ?? "n/a"}ms bytes=${event.payloadBytes ?? "n/a"} cache=${cache}${event.errorCode ? ` err=${event.errorCode}` : ""}`
  )
}

export function measureSync<T>(fn: () => T): { value: T; ms: number } {
  const start =
    typeof performance !== "undefined" ? performance.now() : Date.now()
  const value = fn()
  const end =
    typeof performance !== "undefined" ? performance.now() : Date.now()
  return { value, ms: end - start }
}

export async function measureAsync<T>(
  fn: () => Promise<T>
): Promise<{ value: T; ms: number }> {
  const start =
    typeof performance !== "undefined" ? performance.now() : Date.now()
  const value = await fn()
  const end =
    typeof performance !== "undefined" ? performance.now() : Date.now()
  return { value, ms: end - start }
}

export function utf8ByteLength(value: string): number {
  if (typeof TextEncoder !== "undefined") {
    return new TextEncoder().encode(value).length
  }
  return value.length
}
