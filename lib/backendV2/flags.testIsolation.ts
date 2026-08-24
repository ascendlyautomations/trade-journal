import { __resetBackendV2FlagsForTests } from "./flags.ts"

const BACKEND_V2_ENV_KEYS = [
  "NEXT_PUBLIC_BACKEND_V2_SESSION",
  "NEXT_PUBLIC_BACKEND_V2_DASHBOARD",
  "NEXT_PUBLIC_BACKEND_V2_FEED",
  "NEXT_PUBLIC_BACKEND_V2_PROFILE",
  "NEXT_PUBLIC_BACKEND_V2_MESSAGES",
  "NEXT_PUBLIC_BACKEND_V2_MESSAGING",
  "NEXT_PUBLIC_BACKEND_V2_MESSAGE_THREADS",
  "NEXT_PUBLIC_BACKEND_V2_ROOMS",
  "NEXT_PUBLIC_BACKEND_V2_ROOM_PRESENCE",
  "NEXT_PUBLIC_BACKEND_V2_ACTIVITY",
  "NEXT_PUBLIC_BACKEND_V2_CALENDAR",
  "NEXT_PUBLIC_BACKEND_V2_EXPLORE",
  "NEXT_PUBLIC_BACKEND_V2_LEADERBOARD",
  "NEXT_PUBLIC_BACKEND_V2_TRADE_DETAIL",
  "NEXT_PUBLIC_BACKEND_V2_SETTINGS",
  "NEXT_PUBLIC_BACKEND_V2_PROP_FIRM",
] as const

/**
 * @internal Test-only env isolation for Backend V2 flag resolution.
 * Clears NEXT_PUBLIC_BACKEND_V2_* env reads so defaults tests are order-independent.
 */
export function __withBackendV2EnvIsolatedForTests<T>(fn: () => T): T {
  const saved: Record<string, string | undefined> = {}
  for (const key of BACKEND_V2_ENV_KEYS) {
    saved[key] = process.env[key]
    delete process.env[key]
  }

  __resetBackendV2FlagsForTests()

  try {
    return fn()
  } finally {
    for (const key of BACKEND_V2_ENV_KEYS) {
      if (saved[key] === undefined) {
        delete process.env[key]
      } else {
        process.env[key] = saved[key]
      }
    }
    __resetBackendV2FlagsForTests()
  }
}
