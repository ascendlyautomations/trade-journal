import type { ReactNode } from "react"

import { AUTH_PAGE_CONTAINER_CLASS } from "@/lib/authenticatedPageShell"
import { cn } from "@/app/components/ui/cn"

type AuthenticatedPageContainerProps = {
  children: ReactNode
  className?: string
  /** When true, only max-width + centering (parent supplies padding). */
  noPadding?: boolean
}

/**
 * Single outer content boundary for authenticated web pages (md+ padding).
 * Merge `className` for page-specific mobile padding (max-md:px-*).
 */
export default function AuthenticatedPageContainer({
  children,
  className,
  noPadding = false,
}: AuthenticatedPageContainerProps) {
  return (
    <div
      className={cn(
        noPadding
          ? "mx-auto w-full min-w-0 max-w-[1600px]"
          : AUTH_PAGE_CONTAINER_CLASS,
        className
      )}
    >
      {children}
    </div>
  )
}
