"use client"

import Link from "next/link"
import { usePathname, useRouter } from "next/navigation"
import { useCallback, type ComponentProps, type FocusEvent, type MouseEvent, type TouchEvent } from "react"
import { prefetchRouteOnIntent } from "@/lib/routePrefetch"

type IntentPrefetchLinkProps = ComponentProps<typeof Link>

function hrefToPath(href: IntentPrefetchLinkProps["href"]): string | null {
  if (typeof href === "string") return href
  if (href && typeof href === "object" && "pathname" in href) {
    const pathname = href.pathname
    return typeof pathname === "string" ? pathname : null
  }
  return null
}

/**
 * Next.js Link with viewport prefetch disabled.
 * Prefetches on hover, focus, or touch (intent) to avoid post-login bandwidth contention.
 */
export default function IntentPrefetchLink({
  href,
  prefetch = false,
  onMouseEnter,
  onFocus,
  onTouchStart,
  ...rest
}: IntentPrefetchLinkProps) {
  const router = useRouter()
  const pathname = usePathname() ?? undefined

  const prefetchOnIntent = useCallback(() => {
    const path = hrefToPath(href)
    if (path) prefetchRouteOnIntent(router, path, pathname)
  }, [href, router, pathname])

  return (
    <Link
      href={href}
      prefetch={prefetch}
      onMouseEnter={(event: MouseEvent<HTMLAnchorElement>) => {
        prefetchOnIntent()
        onMouseEnter?.(event)
      }}
      onFocus={(event: FocusEvent<HTMLAnchorElement>) => {
        prefetchOnIntent()
        onFocus?.(event)
      }}
      onTouchStart={(event: TouchEvent<HTMLAnchorElement>) => {
        prefetchOnIntent()
        onTouchStart?.(event)
      }}
      {...rest}
    />
  )
}
