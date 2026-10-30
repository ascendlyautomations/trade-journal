"use client"

import { ChevronLeft } from "lucide-react"
import { useRouter } from "next/navigation"
import { usePathname } from "next/navigation"
import { useIsNativeIos } from "@/lib/useIsNativeIos"
import { resolveMobileWebPageHeader } from "@/lib/mobileWebTabBar"

/**
 * Phone-only inline title + back for secondary routes.
 * Tab roots render nothing. Hidden at md+ so desktop headings stay as-is.
 */
export default function MobileWebPageHeader() {
  const isNativeIos = useIsNativeIos()
  const pathname = usePathname() || "/"
  const router = useRouter()
  const spec = resolveMobileWebPageHeader(pathname)

  if (isNativeIos || !spec) return null

  function handleBack() {
    if (typeof window !== "undefined" && window.history.length > 1) {
      router.back()
      return
    }
    router.push(spec.backHref)
  }

  return (
    <header className="md:hidden flex h-11 shrink-0 items-center gap-0.5 px-2 text-inherit">
      <button
        type="button"
        onClick={handleBack}
        className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-full text-inherit"
        aria-label="Back"
      >
        <ChevronLeft className="h-6 w-6" strokeWidth={2.25} aria-hidden />
      </button>
      <h1 className="min-w-0 truncate text-[17px] font-semibold tracking-tight">
        {spec.title}
      </h1>
    </header>
  )
}
