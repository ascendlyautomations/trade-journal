"use client"

import { memo } from "react"
import InputTradeForm from "./InputTradeForm"
import PerformanceShareModal from "./PerformanceShareModal"
import ShareToConversationsModal from "@/app/components/ShareToConversationsModal"

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
      {selectedImage ? (
        <div
          className="fixed inset-0 bg-black bg-opacity-80 flex items-center justify-center"
          onClick={onCloseImageLightbox}
        >
          <img
            src={selectedImage}
            alt=""
            loading="lazy"
            decoding="async"
            className="max-w-[90%] max-h-[90%] rounded-lg"
          />
        </div>
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
