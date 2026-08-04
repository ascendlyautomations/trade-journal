"use client"

import { useEffect, useRef } from "react"
import Modal from "./Modal"
import { usePlatformPresentation } from "@/app/components/platform/usePlatformPresentation"
import NativeIosPlatformDialog from "@/app/components/platform/native/NativeIosPlatformDialog"

export type ConfirmModalProps = {
  open: boolean
  title: string
  description: string
  confirmLabel?: string
  cancelLabel?: string
  loading?: boolean
  loadingLabel?: string
  destructive?: boolean
  onCancel: () => void
  onConfirm: () => void | Promise<void>
}

function ConfirmActions({
  confirmLabel,
  cancelLabel,
  loading,
  loadingLabel,
  destructive,
  onCancel,
  onConfirm,
}: {
  confirmLabel: string
  cancelLabel: string
  loading: boolean
  loadingLabel: string
  destructive: boolean
  onCancel: () => void
  onConfirm: () => void | Promise<void>
}) {
  return (
    <div className="flex justify-end gap-3">
      <button
        type="button"
        disabled={loading}
        onClick={onCancel}
        className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50"
      >
        {cancelLabel}
      </button>
      <button
        type="button"
        disabled={loading}
        onClick={() => void onConfirm()}
        className={`rounded-lg px-4 py-2 text-sm font-medium text-white transition disabled:cursor-not-allowed disabled:opacity-50 ${
          destructive
            ? "bg-red-600 hover:bg-red-500"
            : "bg-blue-600 hover:bg-blue-500"
        }`}
      >
        {loading ? loadingLabel : confirmLabel}
      </button>
    </div>
  )
}

/** Dark-theme confirmation dialog (Cancel + primary/destructive action). */
export default function ConfirmModal({
  open,
  title,
  description,
  confirmLabel = "Confirm",
  cancelLabel = "Cancel",
  loading = false,
  loadingLabel = "Please wait…",
  destructive = false,
  onCancel,
  onConfirm,
}: ConfirmModalProps) {
  const { isNativeIos } = usePlatformPresentation()
  const wasOpenRef = useRef(false)
  useEffect(() => {
    if (open && !wasOpenRef.current) {
      void import("@/lib/nativeHaptics").then(({ hapticWarning }) => {
        hapticWarning(destructive ? "confirm-destructive" : "confirm")
      })
    }
    wasOpenRef.current = open
  }, [open, destructive])

  const actions = (
    <ConfirmActions
      confirmLabel={confirmLabel}
      cancelLabel={cancelLabel}
      loading={loading}
      loadingLabel={loadingLabel}
      destructive={destructive}
      onCancel={onCancel}
      onConfirm={onConfirm}
    />
  )

  if (isNativeIos) {
    return (
      <NativeIosPlatformDialog
        open={open}
        onClose={loading ? () => {} : onCancel}
        title={title}
        closeDisabled={loading}
        showCloseButton={!loading}
        footer={actions}
      >
        <p className="text-sm leading-relaxed text-gray-300">{description}</p>
      </NativeIosPlatformDialog>
    )
  }

  return (
    <Modal
      open={open}
      onClose={loading ? () => {} : onCancel}
      closeDisabled={loading}
      title={title}
      size="sm"
      footer={actions}
    >
      <p className="text-sm leading-relaxed text-gray-300">{description}</p>
    </Modal>
  )
}
