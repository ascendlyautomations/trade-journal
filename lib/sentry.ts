import type { BrowserOptions, EdgeOptions, NodeOptions } from "@sentry/nextjs"

export function getSentryDsn(): string | undefined {
  return process.env.SENTRY_DSN ?? process.env.NEXT_PUBLIC_SENTRY_DSN
}

export function getSentryEnvironment(): string {
  return process.env.VERCEL_ENV ?? process.env.NODE_ENV ?? "development"
}

export function getBaseSentryOptions():
  | BrowserOptions
  | NodeOptions
  | EdgeOptions {
  const dsn = getSentryDsn()
  return {
    dsn,
    enabled: Boolean(dsn),
    environment: getSentryEnvironment(),
    tracesSampleRate: process.env.NODE_ENV === "production" ? 0.1 : 0,
    debug: process.env.SENTRY_DEBUG === "true",
  }
}
