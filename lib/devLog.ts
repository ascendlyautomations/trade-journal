/**
 * Development-only logging. No-op in production so the browser/server console
 * stays clean during normal usage.
 */

function isDev(): boolean {
  return process.env.NODE_ENV !== "production"
}

export function devLog(...args: unknown[]): void {
  if (isDev()) console.log(...args)
}

export function devWarn(...args: unknown[]): void {
  if (isDev()) console.warn(...args)
}

export function devDebug(...args: unknown[]): void {
  if (isDev()) console.debug(...args)
}

/** Logs in development; always logs in production for genuine monitoring. */
export function devOrProdError(...args: unknown[]): void {
  console.error(...args)
}
