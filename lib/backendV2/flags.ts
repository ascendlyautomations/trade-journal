/**
 * Backend V2 feature flags — all default OFF.
 *
 * Runtime enable (web):
 *   1. NEXT_PUBLIC_BACKEND_V2_<FLAG>=1  (must be static process.env access for Next)
 *   2. localStorage.setItem("backendV2.session", "1") then reload
 *   3. Test-only: __setBackendV2FlagForTests("session", true)
 *
 * Priority: test override > localStorage > env > default(false)
 *
 * IMPORTANT (Next.js): Client bundles only inline statically written
 * `process.env.NEXT_PUBLIC_*` identifiers. Dynamic `process.env[key]` is always
 * undefined in the browser — that previously made env overrides invisible.
 */

export const BackendV2FlagKeys = [
  "session",
  "dashboard",
  "feed",
  "profile",
  "messages",
  "messageThreads",
  "rooms",
  "roomPresence",
  "activity",
  "calendar",
  "explore",
  "leaderboard",
  "tradeDetail",
  "settings",
  "propFirm",
] as const

export type BackendV2FlagKey = (typeof BackendV2FlagKeys)[number]

/** Canonical dotted names for docs / telemetry. */
export const BackendV2FlagNames: Record<BackendV2FlagKey, string> = {
  session: "backendV2.session",
  dashboard: "backendV2.dashboard",
  feed: "backendV2.feed",
  profile: "backendV2.profile",
  messages: "backendV2.messages",
  messageThreads: "backendV2.messageThreads",
  rooms: "backendV2.rooms",
  roomPresence: "backendV2.roomPresence",
  activity: "backendV2.activity",
  calendar: "backendV2.calendar",
  explore: "backendV2.explore",
  leaderboard: "backendV2.leaderboard",
  tradeDetail: "backendV2.tradeDetail",
  settings: "backendV2.settings",
  propFirm: "backendV2.propFirm",
}

const DEFAULTS: Record<BackendV2FlagKey, boolean> = {
  session: false,
  dashboard: false,
  feed: false,
  profile: false,
  messages: false,
  messageThreads: false,
  rooms: false,
  roomPresence: false,
  activity: false,
  calendar: false,
  explore: false,
  leaderboard: false,
  tradeDetail: false,
  settings: false,
  propFirm: false,
}

/**
 * Static env reads — required for Next.js client inlining.
 * Each case must reference process.env.NEXT_PUBLIC_* literally (no dynamic keys).
 */
function envRaw(flag: BackendV2FlagKey): string | undefined {
  switch (flag) {
    case "session":
      return process.env.NEXT_PUBLIC_BACKEND_V2_SESSION
    case "dashboard":
      return process.env.NEXT_PUBLIC_BACKEND_V2_DASHBOARD
    case "feed":
      return process.env.NEXT_PUBLIC_BACKEND_V2_FEED
    case "profile":
      return process.env.NEXT_PUBLIC_BACKEND_V2_PROFILE
    case "messages":
      return (
        process.env.NEXT_PUBLIC_BACKEND_V2_MESSAGES ??
        process.env.NEXT_PUBLIC_BACKEND_V2_MESSAGING
      )
    case "messageThreads":
      return process.env.NEXT_PUBLIC_BACKEND_V2_MESSAGE_THREADS
    case "rooms":
      return process.env.NEXT_PUBLIC_BACKEND_V2_ROOMS
    case "roomPresence":
      return process.env.NEXT_PUBLIC_BACKEND_V2_ROOM_PRESENCE
    case "activity":
      return process.env.NEXT_PUBLIC_BACKEND_V2_ACTIVITY
    case "calendar":
      return process.env.NEXT_PUBLIC_BACKEND_V2_CALENDAR
    case "explore":
      return process.env.NEXT_PUBLIC_BACKEND_V2_EXPLORE
    case "leaderboard":
      return process.env.NEXT_PUBLIC_BACKEND_V2_LEADERBOARD
    case "tradeDetail":
      return process.env.NEXT_PUBLIC_BACKEND_V2_TRADE_DETAIL
    case "settings":
      return process.env.NEXT_PUBLIC_BACKEND_V2_SETTINGS
    case "propFirm":
      return process.env.NEXT_PUBLIC_BACKEND_V2_PROP_FIRM
    default:
      return undefined
  }
}

/** Test-only overrides. */
let testOverrides: Partial<Record<BackendV2FlagKey, boolean>> = {}

function parseBoolFlag(raw: string | null | undefined): boolean | undefined {
  if (raw == null) return undefined
  const v = String(raw).trim().toLowerCase()
  if (v === "1" || v === "true" || v === "on" || v === "yes") return true
  if (v === "0" || v === "false" || v === "off" || v === "no") return false
  return undefined
}

function envOverride(flag: BackendV2FlagKey): boolean | undefined {
  return parseBoolFlag(envRaw(flag))
}

/** localStorage key matches dotted name: backendV2.session */
function localStorageOverride(flag: BackendV2FlagKey): boolean | undefined {
  if (typeof window === "undefined") return undefined
  try {
    return parseBoolFlag(window.localStorage.getItem(BackendV2FlagNames[flag]))
  } catch {
    return undefined
  }
}

export type BackendV2FlagResolution = {
  enabled: boolean
  source: "test" | "localStorage" | "env" | "default"
  /** Debug: raw values observed while resolving. */
  debug: {
    envRaw: string | undefined
    localStorageRaw: string | null | undefined
    testOverride: boolean | undefined
  }
}

export function resolveBackendV2Flag(
  flag: BackendV2FlagKey
): BackendV2FlagResolution {
  let localStorageRaw: string | null | undefined
  try {
    localStorageRaw =
      typeof window !== "undefined"
        ? window.localStorage.getItem(BackendV2FlagNames[flag])
        : undefined
  } catch {
    localStorageRaw = undefined
  }

  const debug = {
    envRaw: envRaw(flag),
    localStorageRaw,
    testOverride: Object.prototype.hasOwnProperty.call(testOverrides, flag)
      ? Boolean(testOverrides[flag])
      : undefined,
  }

  if (Object.prototype.hasOwnProperty.call(testOverrides, flag)) {
    return {
      enabled: Boolean(testOverrides[flag]),
      source: "test",
      debug,
    }
  }
  const fromLocal = localStorageOverride(flag)
  if (fromLocal !== undefined) {
    return { enabled: fromLocal, source: "localStorage", debug }
  }
  const fromEnv = envOverride(flag)
  if (fromEnv !== undefined) {
    return { enabled: fromEnv, source: "env", debug }
  }
  return { enabled: DEFAULTS[flag], source: "default", debug }
}

export function isBackendV2Enabled(flag: BackendV2FlagKey): boolean {
  return resolveBackendV2Flag(flag).enabled
}

export function listBackendV2Flags(): Array<{
  key: BackendV2FlagKey
  name: string
  enabled: boolean
  source: BackendV2FlagResolution["source"]
}> {
  return BackendV2FlagKeys.map((key) => {
    const resolved = resolveBackendV2Flag(key)
    return {
      key,
      name: BackendV2FlagNames[key],
      enabled: resolved.enabled,
      source: resolved.source,
    }
  })
}

/** @internal Contract / unit tests only. */
export function __setBackendV2FlagForTests(
  flag: BackendV2FlagKey,
  enabled: boolean | undefined
): void {
  if (enabled === undefined) {
    delete testOverrides[flag]
  } else {
    testOverrides[flag] = enabled
  }
}

/** @internal */
export function __resetBackendV2FlagsForTests(): void {
  testOverrides = {}
}
