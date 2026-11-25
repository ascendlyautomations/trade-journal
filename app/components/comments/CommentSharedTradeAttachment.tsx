"use client"

import { useRouter } from "next/navigation"
import { useCallback } from "react"
import SharedTradeMessageCard from "@/app/components/SharedTradeMessageCard"
import { getSharedTradeViewHref } from "@/lib/sharedContentNavigation"

type CommentSharedTradeAttachmentProps = {
  tradeId: string
  viewerUserId?: string | null
  className?: string
}

export default function CommentSharedTradeAttachment({
  tradeId,
  viewerUserId,
  className = "mt-2 max-w-md",
}: CommentSharedTradeAttachmentProps) {
  const router = useRouter()

  const handleView = useCallback(
    (trade: { id?: string | null }) => {
      const id = trade.id != null ? String(trade.id) : tradeId
      router.push(getSharedTradeViewHref(id))
    },
    [router, tradeId]
  )

  return (
    <div className={className}>
      <SharedTradeMessageCard
        tradeId={tradeId}
        viewerUserId={viewerUserId}
        onViewTrade={handleView}
        showSocialLayer={false}
        surface="message"
      />
    </div>
  )
}