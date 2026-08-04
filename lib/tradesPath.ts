/** True for the main app Trades route. */
export function isAppTradesPath(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return pathname === "/trades" || pathname.startsWith("/trades/")
}
