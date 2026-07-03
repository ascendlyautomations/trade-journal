import type { Metadata } from "next"
import type { ReactNode } from "react"
import { COOKIE_POLICY_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = COOKIE_POLICY_PAGE_METADATA

export default function CookiePolicyLayout({ children }: { children: ReactNode }) {
  return children
}
