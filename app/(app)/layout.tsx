import Navbar from "../components/Navbar"

/**
 * Persistent authenticated app shell (route group — URLs unchanged).
 *
 * Shared Navbar routes: /dashboard, /trades, /feed, /messages, /analytics/propfirm
 *
 * Contract:
 * - Root layout (`app/layout.tsx`) provides `pt-16` for the fixed Navbar — do not duplicate here.
 * - Render Navbar only in this layout; pages in this group must not import Navbar.
 * - Pages own their background/padding wrappers; no shared gradient shell at this level.
 */
export default function AppShellLayout({
  children,
}: Readonly<{
  children: React.ReactNode
}>) {
  return (
    <>
      <Navbar />
      {children}
    </>
  )
}
