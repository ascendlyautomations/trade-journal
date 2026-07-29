import { isNativeIos } from "@/lib/nativePlatform"
import { supabaseBearerHeaders } from "@/lib/supabaseBearerFetch"

const DENIED_KEY = "tt_ios_push_permission_denied_v1"
const TOKEN_KEY = "tt_ios_push_device_token_v1"

/** TEMPORARY — grep Safari/Xcode/WebView console for this prefix; remove after diagnosis. */
const PUSH_DEBUG = "[tt-push-debug]"

let registrationInFlight: Promise<void> | null = null
let listenersAttached = false
let lastRegisteredToken: string | null = null
/**
 * Capacitor iOS PushNotificationsPlugin sets an internal
 * `appDelegateRegistrationCalled` flag only after AppDelegate posts
 * `.capacitorDidRegisterForRemoteNotifications` (or the fail event).
 * `getDeliveredNotifications` / `removeDeliveredNotifications` reject with
 * "event capacitorDidRegisterForRemoteNotifications not called" until then.
 * `register()` resolves as soon as UIKit is asked to register — it does NOT
 * wait for that callback — so we must not call delivered APIs until this is true.
 */
let apnsBridgeReady = false
/** In-flight per-token posts so registration + stored refresh don't double-hit the API. */
const postRegisterInFlight = new Map<string, Promise<void>>()
let cachedAppVersion: string | null | undefined
let cachedInstallationId: string | null | undefined
/** Once registration proves push is unavailable (e.g. missing aps-environment), skip further attempts this session. */
let pushCapabilityUnavailable = false
/** TEMPORARY — set by registerNativeIosPush for token↔user correlation logs. */
let debugUserId: string | null = null
let appStateDebugListenerAttached = false

/** True after native AppDelegate ↔ Capacitor push bridge has reported register/fail. */
export function isNativeIosPushBridgeReady(): boolean {
  return apnsBridgeReady
}

function pushDebugLog(message: string, data?: Record<string, unknown>) {
  const payload = {
    timestamp: new Date().toISOString(),
    ...(data ?? {}),
  }
  console.info(PUSH_DEBUG, message, payload)
}

/**
 * Mirror of last observed system deny — debug / analytics only.
 * Must NOT gate registration; always re-query checkPermissions().
 */
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

async function resolveInstallationId(): Promise<string | null> {
  if (cachedInstallationId !== undefined) return cachedInstallationId
  cachedInstallationId = null
  try {
    const { Device } = await import("@capacitor/device")
    const { identifier } = await Device.getId()
    const id = typeof identifier === "string" ? identifier.trim() : ""
    cachedInstallationId = id || null
  } catch {
    cachedInstallationId = null
  }
  return cachedInstallationId
}

async function resolveAppVersion(): Promise<string | null> {
  if (cachedAppVersion !== undefined) return cachedAppVersion
  cachedAppVersion = null
  try {
    const { Device } = await import("@capacitor/device")
    const info = await Device.getInfo()
    cachedAppVersion = info.appVersion ?? null
  } catch {
    cachedAppVersion = null
  }
  return cachedAppVersion
}

/**
 * Send the current APNs token to the server.
 * Always includes installationId (IDFV) so rotated tokens replace the prior
 * row for this install. Sends previousDeviceToken when local cache differs.
 */
async function postRegister(deviceToken: string) {
  const token = deviceToken.trim()
  if (!token) return

  // Already confirmed this session — skip redundant network/DB work.
  if (lastRegisteredToken === token) {
    pushDebugLog("postRegister skipped (already registered this session)", {
      deviceToken: token,
      userId: debugUserId,
    })
    return
  }

  const existing = postRegisterInFlight.get(token)
  if (existing) {
    await existing
    return
  }

  const run = (async () => {
    const [appVersion, installationId] = await Promise.all([
      resolveAppVersion(),
      resolveInstallationId(),
    ])

    const previousDeviceToken = getStoredIosPushToken()
    const previous =
      previousDeviceToken && previousDeviceToken !== token
        ? previousDeviceToken
        : null

    pushDebugLog("registration request", {
      userId: debugUserId,
      deviceToken: token,
      previousDeviceToken: previous,
      installationId,
      platform: "ios",
      appVersion,
    })

    const headers = await supabaseBearerHeaders()
    const res = await fetch("/api/push/register", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...headers,
      },
      body: JSON.stringify({
        deviceToken: token,
        previousDeviceToken: previous,
        installationId,
        platform: "ios",
        appVersion,
      }),
    })

    if (!res.ok) {
      const text = await res.text().catch(() => "")
      console.error("[ios-push] registration failed", {
        status: res.status,
        body: text.slice(0, 200),
      })
      pushDebugLog("registration failed", {
        status: res.status,
        body: text.slice(0, 200),
        deviceToken: token,
        userId: debugUserId,
      })
      throw new Error(`register failed: ${res.status} ${text}`)
    }

    pushDebugLog("registration ok", {
      deviceToken: token,
      previousDeviceToken: previous,
      installationId,
      userId: debugUserId,
      rotated: Boolean(previous),
    })

    lastRegisteredToken = token
    persistToken(token)
  })()

  postRegisterInFlight.set(token, run)
  try {
    await run
  } finally {
    postRegisterInFlight.delete(token)
  }
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

async function postMarkReadTarget(body: Record<string, unknown>) {
  const headers = await supabaseBearerHeaders()
  await fetch("/api/notifications/mark-read-target", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...headers,
    },
    body: JSON.stringify(body),
  })
  try {
    window.dispatchEvent(new Event("tj-unread-notifications-refresh"))
    window.dispatchEvent(new Event("tj-unread-messages-refresh"))
  } catch {
    /* ignore */
  }
}

async function handlePushAction(opts: {
  actionId: string
  href: string | null
  inputValue: string
  conversationId: string | null
  roomId: string | null
  roomSlug: string | null
  followRequestId: string | null
  notificationType: string | null
}) {
  const {
    actionId,
    href,
    inputValue,
    conversationId,
    roomId,
    roomSlug,
    followRequestId,
  } = opts

  // Default tap
  if (!actionId || actionId === "tap") {
    if (href) navigateToHref(href)
    else navigateToHref("/notifications")
    return
  }

  if (actionId === "TT_MARK_READ") {
    if (conversationId) {
      await postMarkReadTarget({
        conversationId,
        markConversationRead: true,
      })
      void import("@/lib/clearDeliveredConversationNotifications").then(
        ({ clearDeliveredNotificationsForConversation }) => {
          void clearDeliveredNotificationsForConversation(conversationId)
        }
      )
      return
    }
    if (roomId || roomSlug) {
      await postMarkReadTarget({
        roomId,
        roomSlug,
        markRoomRead: true,
      })
      return
    }
    return
  }

  if (actionId === "TT_REPLY") {
    const base = href || (conversationId ? `/messages/${conversationId}` : "/messages")
    const url = new URL(base, window.location.origin)
    url.searchParams.set("reply", "1")
    if (inputValue) url.searchParams.set("draft", inputValue)
    navigateToHref(url.pathname + url.search)
    return
  }

  if (actionId === "TT_OPEN_ROOM" || actionId === "TT_VIEW_COMMENT") {
    if (href) navigateToHref(href)
    else navigateToHref(actionId === "TT_OPEN_ROOM" ? "/community" : "/notifications")
    return
  }

  if (actionId === "TT_ACCEPT_FOLLOW" || actionId === "TT_DECLINE_FOLLOW") {
    if (!followRequestId) {
      if (href) navigateToHref(href)
      else navigateToHref("/notifications")
      return
    }
    const headers = await supabaseBearerHeaders()
    const path =
      actionId === "TT_ACCEPT_FOLLOW"
        ? "/api/follow-requests/approve"
        : "/api/follow-requests/decline"
    await fetch(path, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...headers,
      },
      body: JSON.stringify({ requestId: followRequestId }),
    }).catch(() => {})
    try {
      window.dispatchEvent(new Event("tj-unread-notifications-refresh"))
    } catch {
      /* ignore */
    }
    return
  }

  if (href) navigateToHref(href)
  else navigateToHref("/notifications")
}

function markPushUnavailable() {
  pushCapabilityUnavailable = true
  listenersAttached = false
  // Failure still means AppDelegate posted the Capacitor event — delivered APIs are allowed.
  apnsBridgeReady = true
}

async function logDeliveredNotifications(reason: string) {
  if (!apnsBridgeReady) {
    pushDebugLog("getDeliveredNotifications skipped (APNs bridge not ready)", {
      reason,
      userId: debugUserId,
    })
    return
  }
  try {
    const { PushNotifications } = await import("@capacitor/push-notifications")
    const delivered = await PushNotifications.getDeliveredNotifications()
    pushDebugLog("getDeliveredNotifications", {
      reason,
      userId: debugUserId,
      count: delivered.notifications?.length ?? 0,
      notifications: delivered.notifications ?? [],
    })
  } catch (err) {
    pushDebugLog("getDeliveredNotifications failed", {
      reason,
      error: err instanceof Error ? err.message : String(err),
    })
  }
}

async function ensureAppStateDebugListener() {
  if (appStateDebugListenerAttached) return
  appStateDebugListenerAttached = true
  try {
    const { App } = await import("@capacitor/app")
    await App.addListener("appStateChange", ({ isActive }) => {
      pushDebugLog("appStateChange", {
        isActive,
        userId: debugUserId,
        visibility:
          typeof document !== "undefined" ? document.visibilityState : null,
      })
      if (isActive) {
        void logDeliveredNotifications("appStateChange:active")
      }
    })
  } catch {
    /* App plugin unavailable */
  }
}

async function ensureListeners(
  onForegroundNotification?: () => void
) {
  if (listenersAttached || pushCapabilityUnavailable) return

  const { PushNotifications } = await import("@capacitor/push-notifications")
  await ensureAppStateDebugListener()

  await PushNotifications.addListener("registration", (token) => {
    apnsBridgeReady = true
    const value = String(token.value ?? "").trim()
    // TEMPORARY [tt-push-debug] — log every registration callback.
    pushDebugLog("PushNotifications registration", {
      deviceToken: value,
      userId: debugUserId,
      platform: "ios",
      alreadyPostedThisSession: lastRegisteredToken === value,
      storedToken: getStoredIosPushToken(),
    })
    void logDeliveredNotifications("after:registration")
    if (!value) return
    // Always forward the current APNs token (rotation / reinstall / launch).
    // postRegister no-ops if this exact token was already posted this session.
    void postRegister(value).catch((err) => {
      console.error("[ios-push] postRegister failed (will retry)", {
        error: err instanceof Error ? err.message : String(err),
      })
      // Retry once after a short delay — silent on failure (e.g. offline).
      window.setTimeout(() => {
        void postRegister(value).catch((retryErr) => {
          console.error("[ios-push] postRegister retry failed", {
            error:
              retryErr instanceof Error ? retryErr.message : String(retryErr),
          })
        })
      }, 2500)
    })
  })

  await PushNotifications.addListener("registrationError", (err) => {
    apnsBridgeReady = true
    pushDebugLog("PushNotifications registrationError", {
      error: err,
      userId: debugUserId,
    })
    console.error("[ios-push] APNs registrationError", err)
    // Missing Push capability / unsigned entitlement — stay quiet for product UX.
    markPushUnavailable()
  })

  // Foreground: refresh in-app unread; messaging types show a lightweight
  // in-app banner when the user is not viewing that conversation/room.
  // (capacitor.config presentationOptions is badge-only — no system banner.)
  await PushNotifications.addListener("pushNotificationReceived", (notification) => {
    // TEMPORARY [tt-push-debug] — fires when app is foregrounded (willPresent path).
    pushDebugLog("PushNotifications pushNotificationReceived", {
      userId: debugUserId,
      title: notification?.title ?? null,
      body: notification?.body ?? null,
      id: notification?.id ?? null,
      data: notification?.data ?? null,
      visibility:
        typeof document !== "undefined" ? document.visibilityState : null,
    })
    void logDeliveredNotifications("after:pushNotificationReceived")

    onForegroundNotification?.()
    try {
      window.dispatchEvent(new Event("tj-unread-notifications-refresh"))
      window.dispatchEvent(new Event("tj-unread-messages-refresh"))
    } catch {
      /* ignore */
    }

    const data = notification?.data as
      | {
          href?: string
          type?: string
          title?: string
          body?: string
        }
      | undefined
    const type = typeof data?.type === "string" ? data.type : ""
    const href = typeof data?.href === "string" ? data.href : ""
    const isMessaging =
      type === "message" || type === "room_message" || type === "room_mention"
    if (!isMessaging || !href) return

    const title =
      (typeof notification?.title === "string" && notification.title) ||
      (typeof data?.title === "string" && data.title) ||
      "New message"
    const body =
      (typeof notification?.body === "string" && notification.body) ||
      (typeof data?.body === "string" && data.body) ||
      ""

    void import("@/lib/messagingActiveContext").then(
      ({ dispatchMessagingInAppBanner, isViewingMessagingTarget }) => {
        if (isViewingMessagingTarget(href)) return
        let conversationId: string | null = null
        let roomSlug: string | null = null
        try {
          const url = new URL(href, window.location.origin)
          if (url.pathname.startsWith("/messages/")) {
            conversationId =
              url.pathname.slice("/messages/".length).split("/")[0] || null
          }
          if (url.pathname.startsWith("/community")) {
            roomSlug = url.searchParams.get("room")
          }
        } catch {
          /* ignore */
        }
        dispatchMessagingInAppBanner({
          title,
          body,
          href,
          conversationId,
          roomSlug,
          notificationType: type,
        })
      }
    )
  })

  await PushNotifications.addListener(
    "pushNotificationActionPerformed",
    (event) => {
      const actionId = String(event.actionId ?? "")
      const data = event.notification?.data as
        | {
            href?: string
            type?: string
            conversationId?: string
            roomId?: string
            roomSlug?: string
            followRequestId?: string
          }
        | undefined
      const href = typeof data?.href === "string" ? data.href : null
      const inputValue =
        typeof event.inputValue === "string" ? event.inputValue.trim() : ""

      // TEMPORARY [tt-push-debug] — tap / action from notification.
      pushDebugLog("PushNotifications pushNotificationActionPerformed", {
        userId: debugUserId,
        actionId,
        inputValue: inputValue || null,
        title: event.notification?.title ?? null,
        body: event.notification?.body ?? null,
        data: event.notification?.data ?? null,
      })

      void handlePushAction({
        actionId,
        href,
        inputValue,
        conversationId: data?.conversationId ?? null,
        roomId: data?.roomId ?? null,
        roomSlug: data?.roomSlug ?? null,
        followRequestId: data?.followRequestId ?? null,
        notificationType: data?.type ?? null,
      })
    }
  )

  listenersAttached = true
}

/**
 * Request permission (once when undetermined), register for APNs, and persist
 * the token. No-ops on web / Android / when system permission is denied / when
 * Push capability is unavailable.
 *
 * Permission source of truth on iOS:
 * - `checkPermissions()` maps UNAuthorizationStatus (matches Settings / UNNotificationSettings).
 * - `requestPermissions()` calls requestAuthorization and maps only the `granted`
 *   Bool — that can disagree with authorizationStatus in edge cases. Only call it
 *   when status is `prompt`, then re-check with checkPermissions().
 * - Never skip checkPermissions based on a sticky localStorage flag; that drifts
 *   after Settings changes or Xcode reinstalls that preserve WKWebView storage.
 */
export async function registerNativeIosPush(opts?: {
  onForegroundNotification?: () => void
  /** TEMPORARY [tt-push-debug] — authenticated user id for token logs. */
  userId?: string | null
}): Promise<void> {
  if (!isNativeIos()) return
  if (pushCapabilityUnavailable) return

  if (opts?.userId) debugUserId = opts.userId.trim() || null

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

      // Always ask Capacitor (→ UNUserNotificationCenter), never trust a cached deny.
      let status = await PushNotifications.checkPermissions()
      pushDebugLog("checkPermissions", {
        userId: debugUserId,
        receive: status.receive,
        stickyDeniedFlag: readDenied(),
      })

      if (status.receive === "prompt") {
        // First-time system prompt only. Do not call this every launch.
        const requested = await PushNotifications.requestPermissions()
        pushDebugLog("requestPermissions result", {
          userId: debugUserId,
          receive: requested.receive,
        })
        // Re-read authorizationStatus — authoritative vs requestAuthorization's Bool.
        status = await PushNotifications.checkPermissions()
        pushDebugLog("checkPermissions after request", {
          userId: debugUserId,
          receive: status.receive,
          requestPermissionsReported: requested.receive,
        })
      }

      if (status.receive === "granted") {
        writeDenied(false)
      } else if (status.receive === "denied") {
        writeDenied(true)
        pushDebugLog("permission denied (authorizationStatus)", {
          userId: debugUserId,
        })
        return
      } else {
        // prompt-with-rationale or unexpected — do not register yet.
        pushDebugLog("permission not granted yet", {
          userId: debugUserId,
          receive: status.receive,
        })
        return
      }

      // Apple: call registerForRemoteNotifications on every launch so APNs
      // returns the current token (unchanged tokens return quickly).
      // Do not POST a cached token here — wait for the `registration` event
      // so rotated tokens replace the previous row via installationId.
      pushDebugLog("PushNotifications.register() calling", {
        userId: debugUserId,
        storedToken: getStoredIosPushToken(),
      })
      // register() only kicks off UIApplication.registerForRemoteNotifications()
      // and resolves immediately. Do NOT call getDeliveredNotifications here —
      // the plugin rejects until AppDelegate posts capacitorDidRegister…
      await PushNotifications.register()
    } catch (err) {
      pushDebugLog("registerNativeIosPush threw", {
        error: err instanceof Error ? err.message : String(err),
        userId: debugUserId,
      })
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
