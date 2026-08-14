/**
 * Clear delivered conversation notifications — Cap PushNotifications API removed.
 * Native iOS clears delivered notifications in the Swift app.
 */
export async function clearDeliveredConversationNotifications(
  _conversationId: string
): Promise<void> {
  // no-op
}
