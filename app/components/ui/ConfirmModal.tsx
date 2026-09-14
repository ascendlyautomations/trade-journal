"use client"

import { useEffect, useRef } from "react"
import Modal from "./Modal"
import { buttonVariants } from "./Button"
import { cn } from "./cn"
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
        className={buttonVariants({ variant: "secondary", size: "md" })}
      >
        {cancelLabel}
      </button>
      <button
        type="button"
        disabled={loading}
        onClick={() => void onConfirm()}
        className={cn(
          buttonVariants({ variant: "primary", size: "md" }),
          destructive &&
            "bg-destructive text-destructive-foreground hover:bg-destructive/90 disabled:hover:bg-destructive"
        )}
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
        <p className="text-sm leading-relaxed text-foreground-secondary">
          {description}
        </p>
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
      <p className="text-sm leading-relaxed text-foreground-secondary">
        {description}
      </p>
    </Modal>
  )
}
