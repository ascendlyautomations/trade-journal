import { isNativeIos } from "@/lib/nativePlatform"
import { isNativeIosPushBridgeReady } from "@/lib/nativeIosPush"

/**
 * Remove delivered system notifications for one DM conversation only.
 * Leaves other conversations' banners untouched (iMessage-style).
 */
export async function clearDeliveredNotificationsForConversation(
  conversationId: string
): Promise<void> {
  const id = conversationId.trim()
  if (!id || typeof window === "undefined" || !isNativeIos()) return
  // Capacitor rejects get/removeDelivered* until AppDelegate registration event.
  if (!isNativeIosPushBridgeReady()) return

  try {
    const { PushNotifications } = await import(
      "@capacitor/push-notifications"
    )
    const { notifications } = await PushNotifications.getDeliveredNotifications()
    if (!notifications?.length) return

    const matching = notifications.filter((n) => {
      const data = (n.data ?? {}) as Record<string, unknown>
      const cid =
        (typeof data.conversationId === "string" && data.conversationId) ||
        (typeof data.conversation_id === "string" && data.conversation_id) ||
        ""
      if (cid === id) return true

      // Fallback: match deep link path when custom data is missing.
      const href =
        (typeof data.href === "string" && data.href) ||
        (typeof n.id === "string" && n.id.includes(id) ? n.id : "")
      if (typeof href === "string" && href.includes(`/messages/${id}`)) {
        return true
      }
      return false
    })

    if (matching.length === 0) return
    await PushNotifications.removeDeliveredNotifications({
      notifications: matching,
    })
  } catch (err) {
    console.warn(
      "[push] clearDeliveredNotificationsForConversation failed",
      err
    )
  }
}
