import type { Metadata } from "next"
import TradeShareCardV2Preview from "@/app/components/TradeShareCardV2Preview"

export const metadata: Metadata = {
  title: "Trade Share Card V2 Preview",
  robots: { index: false, follow: false },
}

export default function TradeShareCardV2PreviewPage() {
  return (
    <main className="min-h-screen bg-[#030712]">
      <TradeShareCardV2Preview />
    </main>
  )
}
