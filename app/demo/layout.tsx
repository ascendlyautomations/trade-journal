import type { Metadata } from "next"
import DemoRouteActivator from "./components/DemoRouteActivator"
import { DEMO_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = DEMO_PAGE_METADATA

export default function DemoLayout({ children }: { children: React.ReactNode }) {
  return (
    <>
      <DemoRouteActivator />
      <main className="min-h-screen bg-gradient-to-b from-[#0a0f1c] via-[#0b1532] to-[#0a2230] text-gray-100">
        {children}
      </main>
    </>
  )
}
