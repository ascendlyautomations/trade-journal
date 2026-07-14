"use client"

import { useCallback, useState } from "react"
import type { ConfirmModalProps } from "./ConfirmModal"

export const DELETE_CHAT_CONFIRM_COPY = {
  title: "Delete Chat",
  description:
    "Are you sure you want to permanently delete this conversation? This action cannot be undone.",
  confirmLabel: "Delete Chat",
  cancelLabel: "Cancel",
  loadingLabel: "Deleting…",
} as const

export function useDeleteChatConfirmation(
  onDelete: (conversationId: string) => Promise<void>
) {
  const [pendingId, setPendingId] = useState<string | null>(null)
  const [deleting, setDeleting] = useState(false)

  const requestDelete = useCallback(
    (conversationId: string) => {
      if (deleting) return
      setPendingId(String(conversationId))
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
    ...DELETE_CHAT_CONFIRM_COPY,
    loading: deleting,
    destructive: true,
    onCancel: cancelDelete,
    onConfirm: confirmDelete,
  }

  return { requestDelete, confirmModalProps }
}
