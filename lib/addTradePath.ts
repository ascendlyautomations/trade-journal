/** True for the Add Trade route (`/app`). */
export function isAppAddTradePath(
  pathname: string | null | undefined
): boolean {
  if (!pathname) return false
  return pathname === "/app" || pathname === "/app/"
}
