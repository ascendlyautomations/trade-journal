"use client"

import { memo } from "react"
import InputTradeForm from "./InputTradeForm"
import PerformanceShareModal from "./PerformanceShareModal"
import ShareToConversationsModal from "@/app/components/ShareToConversationsModal"
import ImageLightbox from "@/app/components/ui/ImageLightbox"

type TradesPageOverlaysProps = {
  selectedImage: string | null
  editingTrade: any | null
  showPerformanceShare: boolean
  sendTradeId: string | null
  tradesForPerformanceSharePool: any[]
  gateProfile: any | null
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
