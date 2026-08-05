/** True for Trade Rooms (`/community`) — not marketing community-guidelines. */
export function isAppCommunityPath(
  pathname: string | null | undefined
): boolean {
  if (!pathname) return false
  return pathname === "/community" || pathname.startsWith("/community/")
}
