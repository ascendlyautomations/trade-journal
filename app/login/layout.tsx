import type { Metadata } from "next"
import type { ReactNode } from "react"
import StandaloneAuthEnvironment from "@/app/components/StandaloneAuthEnvironment"

export const metadata: Metadata = {
  title: "Sign in",
}

/**
 * Standalone auth screen — not under (marketing)/layout; no PublicNavbar or app navbar.
 */
export default function LoginLayout({ children }: { children: ReactNode }) {
  return <StandaloneAuthEnvironment>{children}</StandaloneAuthEnvironment>
}
