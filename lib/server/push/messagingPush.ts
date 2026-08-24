import { after } from "next/server"
import { dispatchPushNotification } from "@/lib/server/push/pushDispatcher"

export type MessagingPushKind = "message" | "room_message"

export type MessagingPushPreferenceKey =
  | "direct_messages_enabled"
  | "story_replies_enabled"
  | "shares_enabled"
  | "room_messages_enabled"

export type MessagingPushInput = {
  recipientUserId: string
  kind: MessagingPushKind
  sender_id: string
  content?: string | null
  /** When set, this Settings key is enforced (in addition to the master switch). */
  preferenceKey?: MessagingPushPreferenceKey
  /** @deprecated Prefer preferenceKey. Kept for call-site compatibility. */
  prefsAlreadyChecked?: boolean
  senderUsername?: string | null
  senderName?: string | null
}

/** Re-export badge helpers so existing imports keep working. */
export {
  countAppIconBadge,
  countServerUnreadDmMessages,
  getAppIconBadge,
  invalidateAppIconBadgeCache,
} from "@/lib/server/push/badgeService"

/**
 * Messaging-only APNs delivery — never inserts into public.notifications.
 * Routes through the shared Push Dispatcher.
 */
export async function deliverMessagingPush(
  input: MessagingPushInput
): Promise<void> {
  const preferenceKey: MessagingPushPreferenceKey =
    input.preferenceKey ??
    (input.kind === "room_message"
      ? "room_messages_enabled"
      : "direct_messages_enabled")

  await dispatchPushNotification({
    recipientUserId: input.recipientUserId,
    type: input.kind,
    sender_id: input.sender_id,
    content: input.content,
    preferenceKey,
    senderUsername: input.senderUsername,
    senderName: input.senderName,
  })
}

/** Schedule messaging push after the HTTP response (Vercel waitUntil via next/server after). */
export function scheduleMessagingPush(input: MessagingPushInput) {
  after(async () => {
    await deliverMessagingPush(input)
  })
}
