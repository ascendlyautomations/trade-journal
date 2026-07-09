import type { Metadata } from "next"
import type { ReactNode } from "react"
import { LOGIN_PAGE_METADATA } from "@/lib/publicRouteMetadata"
import StandaloneAuthEnvironment from "@/app/components/StandaloneAuthEnvironment"

export const metadata: Metadata = LOGIN_PAGE_METADATA

/**
 * Standalone auth screen — not under (marketing)/layout; no PublicNavbar or app navbar.
 */
export default function LoginLayout({ children }: { children: ReactNode }) {
  return <StandaloneAuthEnvironment>{children}</StandaloneAuthEnvironment>
}
