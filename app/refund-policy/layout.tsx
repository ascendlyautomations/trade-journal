import type { Metadata } from "next"
import type { ReactNode } from "react"
import { REFUND_POLICY_PAGE_METADATA } from "@/lib/publicRouteMetadata"

export const metadata: Metadata = REFUND_POLICY_PAGE_METADATA
export const revalidate = 86_400

export default function RefundPolicyLayout({ children }: { children: ReactNode }) {
  return children
}
