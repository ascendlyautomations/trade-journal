import { isNativeIos } from "@/lib/nativePlatform"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"

const DENIED_KEY = "tt_ios_push_permission_denied_v1"
const TOKEN_KEY = "tt_ios_push_device_token_v1"

let registrationInFlight: Promise<void> | null = null
let listenersAttached = false
let lastRegisteredToken: string | null = null
/** Once registration proves push is unavailable (e.g. missing aps-environment), skip further attempts this session. */
let pushCapabilityUnavailable = false

function readDenied(): boolean {
  if (typeof window === "undefined") return false
  try {
    return localStorage.getItem(DENIED_KEY) === "1"
  } catch {
    return false
  }
}

function writeDenied(denied: boolean) {
  if (typeof window === "undefined") return
  try {
    if (denied) localStorage.setItem(DENIED_KEY, "1")
    else localStorage.removeItem(DENIED_KEY)
  } catch {
    /* ignore */
  }
}

function persistToken(token: string | null) {
  if (typeof window === "undefined") return
  try {
    if (token) localStorage.setItem(TOKEN_KEY, token)
    else localStorage.removeItem(TOKEN_KEY)
  } catch {
    /* ignore */
  }
}

export function getStoredIosPushToken(): string | null {
  if (typeof window === "undefined") return null
  try {
    return localStorage.getItem(TOKEN_KEY)
  } catch {
    return null
  }
}

/** TEMPORARY diagnostics — never log full device tokens. Remove after verification. */
function maskDeviceToken(token: string): string {
  const t = token.trim()
  if (t.length < 14) return "***"
  return `${t.slice(0, 8)}...${t.slice(-6)}`
}

async function postRegister(deviceToken: string) {
  const tokenPreview = maskDeviceToken(deviceToken)
  let appVersion: string | null = null
  try {
    const { Device } = await import("@capacitor/device")
    const info = await Device.getInfo()
    appVersion = info.appVersion ?? null
  } catch {
    /* ignore */
  }

  // TEMPORARY diagnostics
  console.info("[ios-push:temp] registration request → /api/push/register", {
    tokenPreview,
  })

  const headers = await supabaseBearerHeaders()
  const res = await fetch("/api/push/register", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...headers,
    },
    body: JSON.stringify({
      deviceToken,
      platform: "ios",
      appVersion,
    }),
  })

  const text = await res.text().catch(() => "")
  // TEMPORARY diagnostics
  console.info("[ios-push:temp] registration response", {
    tokenPreview,
    status: res.status,
    ok: res.ok,
    body: text.slice(0, 200),
  })

  if (!res.ok) {
    console.error("[ios-push:temp] registration failed", {
      tokenPreview,
      status: res.status,
      body: text.slice(0, 200),
    })
    throw new Error(`register failed: ${res.status} ${text}`)
  }
  lastRegisteredToken = deviceToken
  persistToken(deviceToken)
}

async function postUnregister(opts: {
  deviceToken?: string | null
  allDevices?: boolean
}) {
  const headers = await supabaseBearerHeaders()
  const res = await fetch("/api/push/unregister", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...headers,
    },
    body: JSON.stringify({
      deviceToken: opts.deviceToken ?? undefined,
      allDevices: opts.allDevices === true,
    }),
  })
  if (!res.ok) {
    const text = await res.text().catch(() => "")
    throw new Error(`unregister failed: ${res.status} ${text}`)
  }
}

export async function setNativeIosBadgeCount(count: number) {
  if (!isNativeIos()) return
  try {
    const { Badge } = await import("@capawesome/capacitor-badge")
    const n = Math.max(0, Math.floor(count))
    if (n <= 0) await Badge.clear()
    else await Badge.set({ count: n })
  } catch {
    // Badge plugin unavailable — APNs payload still sets badge on next push.
  }
}

function navigateToHref(href: string) {
  if (typeof window === "undefined") return
  const path = href.trim()
  if (!path.startsWith("/")) return
  const custom = (
    window as unknown as { __ttPushNavigate?: (h: string) => void }
  ).__ttPushNavigate
  if (typeof custom === "function") {
    custom(path)
    return
  }
  if (window.location.pathname + window.location.search === path) return
  window.location.assign(path)
}

function markPushUnavailable() {
  pushCapabilityUnavailable = true
  listenersAttached = false
}

async function ensureListeners(
  onForegroundNotification?: () => void
) {
  if (listenersAttached || pushCapabilityUnavailable) return

  const { PushNotifications } = await import("@capacitor/push-notifications")

  await PushNotifications.addListener("registration", (token) => {
    const value = String(token.value ?? "").trim()
    if (!value) return
    // TEMPORARY diagnostics — masked token only
    console.info("[ios-push:temp] APNs token received from iOS", {
      tokenPreview: maskDeviceToken(value),
    })
    void postRegister(value).catch((err) => {
      console.error("[ios-push:temp] postRegister failed (will retry)", {
        tokenPreview: maskDeviceToken(value),
        error: err instanceof Error ? err.message : String(err),
      })
      // Retry once after a short delay — silent on failure (e.g. offline).
      window.setTimeout(() => {
        void postRegister(value).catch((retryErr) => {
          console.error("[ios-push:temp] postRegister retry failed", {
            tokenPreview: maskDeviceToken(value),
            error:
              retryErr instanceof Error ? retryErr.message : String(retryErr),
          })
        })
      }, 2500)
    })
  })

  await PushNotifications.addListener("registrationError", (err) => {
    // TEMPORARY diagnostics
    console.error("[ios-push:temp] APNs registrationError", err)
    // Missing Push capability / unsigned entitlement — stay quiet for product UX.
    markPushUnavailable()
  })

  // Foreground: refresh in-app unread; do not present a duplicate banner
  // (capacitor.config presentationOptions is badge-only).
  await PushNotifications.addListener("pushNotificationReceived", () => {
    onForegroundNotification?.()
    try {
      window.dispatchEvent(new Event("tj-unread-notifications-refresh"))
    } catch {
      /* ignore */
    }
  })

  await PushNotifications.addListener(
    "pushNotificationActionPerformed",
    (event) => {
      const data = event.notification?.data as
        | { href?: string }
        | undefined
      const href = typeof data?.href === "string" ? data.href : null
      if (href) navigateToHref(href)
      else navigateToHref("/notifications")
    }
  )

  listenersAttached = true
}

/**
 * Request permission (once), register for APNs, and persist the token.
 * No-ops on web / Android / when previously denied / when Push capability
 * is unavailable (e.g. missing aps-environment or failed registration).
 */
export async function registerNativeIosPush(opts?: {
  onForegroundNotification?: () => void
}): Promise<void> {
  if (!isNativeIos()) return
  if (pushCapabilityUnavailable) return
  if (readDenied()) return

  if (registrationInFlight) {
    await registrationInFlight
    return
  }

  registrationInFlight = (async () => {
    try {
      await ensureListeners(opts?.onForegroundNotification)
      if (pushCapabilityUnavailable) return

      const { PushNotifications } = await import(
        "@capacitor/push-notifications"
      )

      const current = await PushNotifications.checkPermissions()
      let receive = current.receive

      if (receive === "denied") {
        writeDenied(true)
        return
      }

      if (receive === "prompt") {
        const requested = await PushNotifications.requestPermissions()
        receive = requested.receive
        if (receive !== "granted") {
          writeDenied(true)
          return
        }
        writeDenied(false)
      }

      if (receive !== "granted") return

      // Refresh last_seen / reassign user even when iOS does not re-emit
      // `registration` (common when the token is already known).
      const stored = getStoredIosPushToken()
      if (stored) {
        void postRegister(stored).catch(() => {})
      }

      await PushNotifications.register()
    } catch {
      // Plugin missing, entitlement absent, or bridge error — skip quietly.
      markPushUnavailable()
    } finally {
      registrationInFlight = null
    }
  })()

  await registrationInFlight
}

/** Call before/during sign-out so the token is not left on the prior account. */
export async function unregisterNativeIosPush(opts?: {
  allDevices?: boolean
}): Promise<void> {
  if (!isNativeIos()) return
  const token = lastRegisteredToken ?? getStoredIosPushToken()
  if (!token && !opts?.allDevices) return
  try {
    if (opts?.allDevices) {
      await postUnregister({ allDevices: true })
    } else if (token) {
      await postUnregister({ deviceToken: token })
    }
  } catch {
    // Silent — push may be disabled for this build.
  } finally {
    lastRegisteredToken = null
    persistToken(null)
  }
}
