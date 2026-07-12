import type { Metadata, ReactNode } from "next"

export const metadata: Metadata = {
  title: "TradeTraxs Marketing Ads",
  robots: { index: false, follow: false },
}

/**
 * Chrome-free Instagram ad frames (1080×1350).
 * Opted out of app/marketing navbars via layoutChrome + appNavbarShell.
 */
export default function MarketingAdsLayout({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-screen items-start justify-center bg-[#030712] [&_nextjs-portal]:hidden">
      {children}
    </div>
  )
}
