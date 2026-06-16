"use client"

import { useCallback, useState } from "react"
import type { ConfirmModalProps } from "./ConfirmModal"

export const DELETE_TRADE_CONFIRM_COPY = {
  title: "Delete Trade",
  description:
    "Are you sure you want to delete this trade? This action cannot be undone.",
  confirmLabel: "Delete Trade",
  cancelLabel: "Cancel",
} as const

export function useDeleteTradeConfirmation(
  onDelete: (id: string) => Promise<void>
) {
  const [pendingId, setPendingId] = useState<string | null>(null)
  const [deleting, setDeleting] = useState(false)

  const requestDelete = useCallback(
    (id: string) => {
      if (deleting) return
      setPendingId(String(id))
    },
    [deleting]
  )

  const cancelDelete = useCallback(() => {
    if (deleting) return
    setPendingId(null)
  }, [deleting])

  const confirmDelete = useCallback(async () => {
    if (!pendingId || deleting) return
    setDeleting(true)
    try {
      await onDelete(pendingId)
      setPendingId(null)
    } finally {
      setDeleting(false)
    }
  }, [deleting, onDelete, pendingId])

  const confirmModalProps: ConfirmModalProps = {
    open: pendingId != null,
    ...DELETE_TRADE_CONFIRM_COPY,
    loading: deleting,
    destructive: true,
    onCancel: cancelDelete,
    onConfirm: confirmDelete,
  }

  return { requestDelete, confirmModalProps }
}
