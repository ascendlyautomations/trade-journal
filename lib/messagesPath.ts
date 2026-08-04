/** True for the Messages inbox (`/messages`) — not DM conversation threads. */
export function isAppMessagesInboxPath(
  pathname: string | null | undefined
): boolean {
  if (!pathname) return false
  return pathname === "/messages" || pathname === "/messages/"
}
