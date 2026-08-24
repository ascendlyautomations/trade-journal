import { after } from "next/server"
import {
  dispatchPushNotification,
  type PushDispatchInput,
} from "@/lib/server/push/pushDispatcher"
import type { PushNotificationTarget } from "@/lib/server/push/pushCopy"

export type DeliverPushInput = PushNotificationTarget & {
  recipientUserId: string
  /** @deprecated Preference re-check always runs in the shared dispatcher. */
  prefsAlreadyChecked?: boolean
}

/**
 * Activity notification → shared Push Dispatcher.
 * Extends an existing in-app notification with an optional iOS APNs push.
 */
export async function deliverIosPushNotification(
  input: DeliverPushInput
): Promise<void> {
  const dispatchInput: PushDispatchInput = {
    ...input,
    recipientUserId: input.recipientUserId,
  }
  await dispatchPushNotification(dispatchInput)
}

/** Schedule Activity push after the HTTP response (Vercel waitUntil via next/server after). */
export function scheduleIosPushDelivery(input: DeliverPushInput) {
  after(async () => {
    await deliverIosPushNotification(input)
  })
}
