import type { Metadata } from "next"
import type { ReactNode } from "react"
import { RESET_PASSWORD_PAGE_METADATA } from "@/lib/seoAppPages"
import StandaloneAuthEnvironment from "@/app/components/StandaloneAuthEnvironment"

export const metadata: Metadata = RESET_PASSWORD_PAGE_METADATA

export default function ResetPasswordLayout({ children }: { children: ReactNode }) {
  return <StandaloneAuthEnvironment>{children}</StandaloneAuthEnvironment>
}
