/**
 * k6 request outcome counters (timeout vs HTTP status). Does not change thresholds.
 */

import { Counter, Trend } from "k6/metrics"

export const httpOutcome = new Counter("tradetraxs_http_outcome")
/** Duration recorded only for successful HTTP responses (excludes client timeouts). */
export const httpOkDuration = new Trend("tradetraxs_ok_duration", true)

export function recordHttpOutcome(res, kind, pageTag) {
  const label = kind || "unknown"
  const page = pageTag || label
  if (!res) {
    httpOutcome.add(1, { kind: label, page: page, result: "no_response" })
    return
  }
  if (res.status === 0) {
    httpOutcome.add(1, { kind: label, page: page, result: "client_timeout" })
    return
  }
  if (res.status >= 200 && res.status < 300) {
    httpOutcome.add(1, { kind: label, page: page, result: "ok" })
    if (res.timings && res.timings.duration != null) {
      httpOkDuration.add(res.timings.duration, { kind: label, page: page })
    }
    return
  }
  if (res.status >= 500) {
    httpOutcome.add(1, { kind: label, page: page, result: "server_error" })
    return
  }
  httpOutcome.add(1, { kind: label, page: page, result: "client_error" })
}
