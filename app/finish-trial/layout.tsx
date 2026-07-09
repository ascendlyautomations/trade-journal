import type { Metadata } from "next"
import type { ReactNode } from "react"
import { FINISH_TRIAL_PAGE_METADATA } from "@/lib/seoAppPages"

export const metadata: Metadata = FINISH_TRIAL_PAGE_METADATA

export default function FinishTrialLayout({ children }: { children: ReactNode }) {
  return children
}
