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
      className="fixed inset-0 z-[9000] flex flex-col bg-zinc-950 text-white"
      data-broadcast-studio-mode={mode}
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

      <div className="flex min-h-0 flex-1 flex-col p-3">
        {toolbar ? <div className="mb-2 shrink-0">{toolbar}</div> : null}
        <div className="flex min-h-0 flex-1 flex-col gap-3 lg:flex-row lg:items-stretch">
          <div className="flex min-h-0 w-full min-w-0 flex-1 flex-col">
            {videoColumnPrefix}
            <div className="relative min-h-0 w-full flex-1 overflow-hidden rounded-xl bg-black aspect-video max-lg:max-h-[min(50vh,56vw)] lg:aspect-auto lg:min-h-[280px]">
              {video}
            </div>
          </div>
          {sidebar ? (
            <div className="flex w-full min-h-0 flex-col max-lg:min-h-[220px] lg:w-[min(380px,38vw)] lg:shrink-0">
              {sidebar}
            </div>
          ) : null}
        </div>
      </div>

      {confirmDialog}
    </div>
  )
}
