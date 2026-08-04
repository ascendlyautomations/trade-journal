/** True for the main app Dashboard route (not affiliate/marketing dashboards). */
export function isAppDashboardPath(pathname: string | null | undefined): boolean {
  if (!pathname) return false
  return pathname === "/dashboard" || pathname.startsWith("/dashboard/")
}
