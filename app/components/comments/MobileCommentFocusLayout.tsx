"use client"

import type { ReactNode } from "react"
import { useMaxMdViewport } from "@/lib/useMaxMdViewport"
import { DETAIL_MODAL_PANEL_ENGAGEMENT_CLASS } from "@/app/components/ui/detailModalEngagement"

type MobileCommentFocusLayoutProps = {
  /** User intentionally opened/focused comments (💬, deep link, etc.). */
  commentsFocused: boolean
  /** Full author/header block (desktop + mobile unfocused). */
  header?: ReactNode
  /** Compact strip replacing header on focused mobile. */
  compactHeader?: ReactNode
  /** Like/comment engagement row — stays visible when focused. */
  engagement?: ReactNode
  /** Trade stats, descriptions, timing, etc. */
  collapsibleContent?: ReactNode
  /** Comment list + composer — grows when focused on mobile. */
  comments: ReactNode
  /** Screenshot shown above panel on mobile (hidden when focused). */
  mobileMedia?: ReactNode
  /** Profile trade modal — media + actions above author header on mobile. */
  mobileMediaBeforeHeader?: boolean
  /** When true, engagement row renders below collapsible content (public trade page). */
  engagementAfterCollapsible?: boolean
  engagementClassName?: string
}

/**
 * Mobile-only: collapses heavy content when comments are focused so the thread
 * gets maximum viewport space. Desktop layout is unchanged.
 */
export default function MobileCommentFocusLayout({
  commentsFocused,
  header,
  compactHeader,
  engagement,
  collapsibleContent,
  comments,
  mobileMedia,
  mobileMediaBeforeHeader = false,
  engagementAfterCollapsible = false,
  engagementClassName = DETAIL_MODAL_PANEL_ENGAGEMENT_CLASS,
}: MobileCommentFocusLayoutProps) {
  const isMobile = useMaxMdViewport()
  const collapse = isMobile && commentsFocused

  const engagementBlock =
    engagement ? <div className={engagementClassName}>{engagement}</div> : null

  const collapsibleBlock =
    collapsibleContent ? (
      <div
        className={
          collapse
            ? "max-md:pointer-events-none max-md:max-h-0 max-md:overflow-hidden max-md:opacity-0 max-md:transition-[max-height,opacity] max-md:duration-200 max-md:ease-out"
            : "shrink-0 max-md:transition-[max-height,opacity] max-md:duration-200 max-md:ease-out"
        }
        aria-hidden={collapse || undefined}
      >
        {collapsibleContent}
      </div>
    ) : null

  const mobileMediaBlock =
    mobileMedia && !collapse ? (
      <div className="shrink-0 md:hidden">{mobileMedia}</div>
    ) : null

  const headerBlock =
    collapse && compactHeader ? (
      <div className="shrink-0 border-b border-white/10">{compactHeader}</div>
    ) : header ? (
      <div className="shrink-0">{header}</div>
    ) : null

  return (
    <div className="flex min-h-0 flex-1 flex-col overflow-hidden">
      {mobileMediaBeforeHeader ? mobileMediaBlock : null}
      {headerBlock}
      {!mobileMediaBeforeHeader ? mobileMediaBlock : null}

      {engagementAfterCollapsible ? null : engagementBlock}
      {collapsibleBlock}
      {engagementAfterCollapsible ? engagementBlock : null}

      <div className="flex min-h-0 flex-1 flex-col overflow-hidden">{comments}</div>
    </div>
  )
}
