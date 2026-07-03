import type { ReactNode } from "react"
import MarketingGateShell from "@/app/components/MarketingGateShell"
import PublicNavbar from "@/app/components/PublicNavbar"

/** Marketing site only — homepage, FAQ, pricing, about. Auth/app flow uses separate routes. */
export const revalidate = 86_400

export default function MarketingLayout({ children }: { children: ReactNode }) {
  return (
    <MarketingGateShell>
      <PublicNavbar />
      {children}
    </MarketingGateShell>
  )
}
