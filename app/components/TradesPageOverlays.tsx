"use client"

import dynamic from "next/dynamic"
import { memo } from "react"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import DetailModalShell from "@/app/components/ui/DetailModalShell"
import TradesPageTradeCard from "@/app/components/TradesPageTradeCard"
import type { ReelRow } from "@/lib/reels"

const InputTradeForm = dynamic(() => import("./InputTradeForm"), { ssr: false })
const PerformanceShareModal = dynamic(() => import("./PerformanceShareModal"), {
  ssr: false,
})
const ShareToConversationsModal = dynamic(
  () => import("@/app/components/ShareToConversationsModal"),
  { ssr: false }
)

type TradesPageOverlaysProps = {
  selectedImage: string | null
  selectedTrade: any | null
  editingTrade: any | null
  showPerformanceShare: boolean
  sendTradeId: string | null
  tradesForPerformanceSharePool: any[]
  gateProfile: any | null
  customRangeStart?: string
  customRangeEnd?: string
  accountById?: Record<string, any>
  attachedReel?: ReelRow | null
  onCloseImageLightbox: () => void
  onCloseSelectedTrade: () => void
  onCloseEditForm: () => void
  onTradeFormSaved: () => void
  onClosePerformanceShare: () => void
  onCloseSendModal: () => void
  onEditTrade: (trade: any) => void
  onDeleteTrade: (tradeId: string) => void
  onSendTrade: (trade: any) => void
  onAnalyzeTrade?: (trade: any) => void
  onImageClick: (imageUrl: string) => void
  onOpenTradeReplay?: (trade: any) => void
  onTradeUpdated?: (trade: any) => void
}

function TradesPageOverlays({
  selectedImage,
  selectedTrade,
  editingTrade,
  showPerformanceShare,
  sendTradeId,
  tradesForPerformanceSharePool,
  gateProfile,
  customRangeStart = "",
  customRangeEnd = "",
  accountById = {},
  attachedReel = null,
  onCloseImageLightbox,
  onCloseSelectedTrade,
  onCloseEditForm,
  onTradeFormSaved,
  onClosePerformanceShare,
  onCloseSendModal,
  onEditTrade,
  onDeleteTrade,
  onSendTrade,
  onAnalyzeTrade,
  onImageClick,
  onOpenTradeReplay,
  onTradeUpdated,
}: TradesPageOverlaysProps) {
  return (
    <>
      <ImageLightbox imageUrl={selectedImage} onClose={onCloseImageLightbox} />

      {selectedTrade && !editingTrade ? (
        <DetailModalShell
          ariaLabel="Trade details"
          title="Trade"
          onClose={onCloseSelectedTrade}
        >
          <div className="min-h-0 flex-1 overflow-y-auto p-3">
            <TradesPageTradeCard
              trade={selectedTrade}
              accountRow={accountById[String(selectedTrade.account_id ?? "")]}
              accounts={Object.values(accountById)}
              shareProfile={gateProfile}
              attachedReel={attachedReel}
              onOpenReplay={
                onOpenTradeReplay
                  ? () => onOpenTradeReplay(selectedTrade)
                  : undefined
              }
              onEdit={onEditTrade}
              onDelete={onDeleteTrade}
              onSendClick={onSendTrade}
              onAnalyze={onAnalyzeTrade}
              onImageClick={onImageClick}
              onTradeUpdated={onTradeUpdated}
            />
          </div>
        </DetailModalShell>
      ) : null}

      {editingTrade ? (
        <InputTradeForm
          key={String(editingTrade.id)}
          existingTrade={editingTrade}
          onClose={onCloseEditForm}
          onSave={() => void onTradeFormSaved()}
        />
      ) : null}

      {showPerformanceShare ? (
        <PerformanceShareModal
          open
          onClose={onClosePerformanceShare}
          tradePool={tradesForPerformanceSharePool}
          subtitle="Matches account, mode & date filters"
          profile={gateProfile}
          initialCustomRangeStart={customRangeStart}
          initialCustomRangeEnd={customRangeEnd}
        />
      ) : null}

      {sendTradeId ? (
        <ShareToConversationsModal
          key={sendTradeId}
          open
          onClose={onCloseSendModal}
          title="Send trade"
          tradeId={sendTradeId}
        />
      ) : null}
    </>
  )
}

export default memo(TradesPageOverlays)
