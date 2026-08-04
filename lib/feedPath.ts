/** True for the main app Feed route. */
export function isAppFeedPath(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return pathname === "/feed" || pathname.startsWith("/feed/")
}
