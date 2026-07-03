"use client"

import dynamic from "next/dynamic"
import { memo } from "react"
import ImageLightbox from "@/app/components/ui/ImageLightbox"

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
  editingTrade: any | null
  showPerformanceShare: boolean
  sendTradeId: string | null
  tradesForPerformanceSharePool: any[]
  gateProfile: any | null
  customRangeStart?: string
  customRangeEnd?: string
  onCloseImageLightbox: () => void
  onCloseEditForm: () => void
  onTradeFormSaved: () => void
  onClosePerformanceShare: () => void
  onCloseSendModal: () => void
}

function TradesPageOverlays({
  selectedImage,
  editingTrade,
  showPerformanceShare,
  sendTradeId,
  tradesForPerformanceSharePool,
  gateProfile,
  customRangeStart = "",
  customRangeEnd = "",
  onCloseImageLightbox,
  onCloseEditForm,
  onTradeFormSaved,
  onClosePerformanceShare,
  onCloseSendModal,
}: TradesPageOverlaysProps) {
  return (
    <>
      <ImageLightbox imageUrl={selectedImage} onClose={onCloseImageLightbox} />

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
