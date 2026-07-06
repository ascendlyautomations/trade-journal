"use client"

import { useCallback, useMemo, useState } from "react"
import { isTradeAttachedReel } from "@/lib/reels"
import type { ConfirmModalProps } from "./ConfirmModal"

export const DELETE_REPLAY_CONFIRM_COPY = {
  title: "Delete Replay?",
  description:
    "Are you sure you want to delete this replay? This action cannot be undone.",
  confirmLabel: "Delete Replay",
  cancelLabel: "Cancel",
} as const

export const DELETE_REEL_CONFIRM_COPY = {
  title: "Delete Clip?",
  description:
    "Are you sure you want to delete this clip? This action cannot be undone.",
  confirmLabel: "Delete Clip",
  cancelLabel: "Cancel",
} as const

export function useDeleteReelConfirmation(
  onDelete: (post: any) => Promise<void>
) {
  const [pendingPost, setPendingPost] = useState<any | null>(null)
  const [deleting, setDeleting] = useState(false)

  const requestDelete = useCallback(
    (post: any) => {
      if (deleting) return
      setPendingPost(post)
    },
    [deleting]
  )

  const cancelDelete = useCallback(() => {
    if (deleting) return
    setPendingPost(null)
  }, [deleting])

  const confirmDelete = useCallback(async () => {
    if (!pendingPost || deleting) return
    setDeleting(true)
    try {
      await onDelete(pendingPost)
      setPendingPost(null)
    } finally {
      setDeleting(false)
    }
  }, [deleting, onDelete, pendingPost])

  const copy = useMemo(
    () =>
      pendingPost && isTradeAttachedReel(pendingPost)
        ? DELETE_REPLAY_CONFIRM_COPY
        : DELETE_REEL_CONFIRM_COPY,
    [pendingPost]
  )

  const confirmModalProps: ConfirmModalProps = {
    open: pendingPost != null,
    ...copy,
    loading: deleting,
    destructive: true,
    onCancel: cancelDelete,
    onConfirm: confirmDelete,
  }

  return { requestDelete, confirmModalProps }
}
