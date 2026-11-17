"use client"

import type { ReactNode } from "react"

export type TradeRoomBroadcastStudioShellMode = "host" | "viewer" | "moderator"

type Props = {
  mode: TradeRoomBroadcastStudioShellMode
  title: string
  headerMeta: ReactNode
  headerActions?: ReactNode
  /** Full-width controls above the video + sidebar row (viewer / moderator). */
  toolbar?: ReactNode
  /** Controls stacked above the video in the left column (host). */
  videoColumnPrefix?: ReactNode
  video: ReactNode
  sidebar: ReactNode | null
  confirmDialog?: ReactNode
}

export default function TradeRoomBroadcastStudioShell({
  mode,
  title,
  headerMeta,
  headerActions,
  toolbar,
  videoColumnPrefix,
  video,
  sidebar,
  confirmDialog,
}: Props) {
  return (
    <div
      className="fixed inset-0 z-[10040] flex flex-col bg-zinc-950 pt-[env(safe-area-inset-top,0px)] pb-[env(safe-area-inset-bottom,0px)] text-white"
      data-broadcast-studio-mode={mode}
      data-tt-broadcast-media="true"
    >
      <header className="flex shrink-0 items-center gap-3 border-b border-white/10 px-4 py-3">
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold">{title}</p>
          <div className="flex flex-wrap items-center gap-2 text-xs text-white/70">
            {headerMeta}
          </div>
        </div>
        {headerActions}
      </header>

      <div className="flex min-h-0 flex-1 flex-col overflow-y-auto p-3">
        {toolbar ? <div className="mb-2 shrink-0">{toolbar}</div> : null}
        <div className="flex flex-col gap-3 lg:min-h-0 lg:flex-1 lg:flex-row lg:items-stretch lg:overflow-hidden">
          <div className="flex w-full min-w-0 flex-col lg:min-h-0 lg:flex-1">
            {videoColumnPrefix}
            <div className="relative aspect-video w-full overflow-hidden rounded-xl bg-black lg:aspect-auto lg:min-h-[280px] lg:flex-1">
              {video}
            </div>
          </div>
          {sidebar ? (
            <div className="flex min-h-[220px] w-full flex-col lg:min-h-0 lg:w-[min(380px,38vw)] lg:shrink-0">
              {sidebar}
            </div>
          ) : null}
        </div>
      </div>

      {confirmDialog}
    </div>
  )
}
