"use client"

import dynamic from "next/dynamic"
import type { ComponentProps } from "react"
import type { DashboardTradeRow } from "./dashboardTypes"

const PerformanceShareModal = dynamic(
  () => import("../PerformanceShareModal"),
  { ssr: false }
)
const QuickTradeModal = dynamic(() => import("../QuickTradeModal"), {
  ssr: false,
})
const PostSetupImportModal = dynamic(
  () => import("../PostSetupImportModal"),
  { ssr: false }
)
const TradesPageOverlays = dynamic(() => import("../TradesPageOverlays"), {
  ssr: false,
})

const NOOP = () => {}
const EMPTY_TRADES: DashboardTradeRow[] = []

type DashboardModalsProps = {
  importOpen: boolean
  onImportComplete: () => void
  performanceShareOpen: boolean
  onClosePerformanceShare: () => void
  performanceShareTrades: DashboardTradeRow[]
  profile: ComponentProps<typeof PerformanceShareModal>["profile"]
  customRangeStart: string
  customRangeEnd: string
  quickTradeOpen: boolean
  userId: string | null
  onCloseQuickTrade: () => void
  selectedImage: string | null
  editingTrade: DashboardTradeRow | null
  sendTradeId: string | null
  onCloseImage: () => void
  onCloseTrade: () => void
  onCloseSend: () => void
}

export default function DashboardModals({
  importOpen,
  onImportComplete,
  performanceShareOpen,
  onClosePerformanceShare,
  performanceShareTrades,
  profile,
  customRangeStart,
  customRangeEnd,
  quickTradeOpen,
  userId,
  onCloseQuickTrade,
  selectedImage,
  editingTrade,
  sendTradeId,
  onCloseImage,
  onCloseTrade,
  onCloseSend,
}: DashboardModalsProps) {
  return (
    <>
      {importOpen ? (
        <PostSetupImportModal open onComplete={onImportComplete} />
      ) : null}

      {performanceShareOpen ? (
        <PerformanceShareModal
          open
          onClose={onClosePerformanceShare}
          tradePool={performanceShareTrades}
          subtitle="Dashboard · respects account, mode, date & public filters"
          profile={profile}
          initialCustomRangeStart={customRangeStart}
          initialCustomRangeEnd={customRangeEnd}
        />
      ) : null}

      {quickTradeOpen ? (
        <QuickTradeModal open userId={userId} onClose={onCloseQuickTrade} />
      ) : null}

      {selectedImage || editingTrade || sendTradeId ? (
        <TradesPageOverlays
          selectedImage={selectedImage}
          editingTrade={editingTrade}
          showPerformanceShare={false}
          sendTradeId={sendTradeId}
          tradesForPerformanceSharePool={EMPTY_TRADES}
          gateProfile={null}
          onCloseImageLightbox={onCloseImage}
          onCloseEditForm={onCloseTrade}
          onTradeFormSaved={onCloseTrade}
          onClosePerformanceShare={NOOP}
          onCloseSendModal={onCloseSend}
        />
      ) : null}
    </>
  )
}
