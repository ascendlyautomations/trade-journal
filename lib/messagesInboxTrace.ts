/** Temporary inbox pipeline tracing — always logs (including production). */

export function traceMessagesInbox(
  step: string,
  payload?: Record<string, unknown>
) {
  console.log("[messages-inbox-trace]", step, payload ?? {})
}
