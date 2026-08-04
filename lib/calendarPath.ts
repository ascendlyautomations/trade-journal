/** True for the main app Calendar route. */
export function isAppCalendarPath(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return pathname === "/calendar" || pathname.startsWith("/calendar/")
}
