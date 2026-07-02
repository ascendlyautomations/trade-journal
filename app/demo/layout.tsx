import type { Metadata } from "next"
import DemoRouteActivator from "./components/DemoRouteActivator"

export const metadata: Metadata = {
  title: "Interactive Demo",
  robots: { index: true, follow: true },
}

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
