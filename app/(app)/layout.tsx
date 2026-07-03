/**
 * Persistent authenticated app shell (route group — URLs unchanged).
 *
 * Routes: /dashboard, /trades, /feed, /messages, /analytics/propfirm,
 * /affiliate/dashboard
 *
 * Contract:
 * - Root layout renders `AppNavbarShell` once (portaled fixed header).
 * - Pages in this group must not import Navbar.
 * - Root layout `AppShellPadding` provides top offset for the fixed Navbar.
 */
export default function AppShellLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return <>{children}</>
}
