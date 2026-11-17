"use client"

import Modal from "@/app/components/ui/Modal"
import { buttonVariants } from "@/app/components/ui/Button"
import { cn } from "@/app/components/ui/cn"
import { usePlatformPresentation } from "@/app/components/platform/usePlatformPresentation"
import NativeIosPlatformDialog from "@/app/components/platform/native/NativeIosPlatformDialog"

type Props = {
  open: boolean
  saving: boolean
  onKeepEditing: () => void
  onDiscard: () => void
  onSaveAndExit: () => void | Promise<void>
}

function Actions({
  saving,
  onKeepEditing,
  onDiscard,
  onSaveAndExit,
}: Omit<Props, "open">) {
  return (
    <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap sm:justify-end">
      <button
        type="button"
        disabled={saving}
        onClick={onKeepEditing}
        className={buttonVariants({ variant: "secondary", size: "md" })}
      >
        Keep Editing
      </button>
      <button
        type="button"
        disabled={saving}
        onClick={onDiscard}
        className={cn(
          buttonVariants({ variant: "secondary", size: "md" }),
          "text-red-300 hover:bg-red-500/15"
        )}
      >
        Discard Changes
      </button>
      <button
        type="button"
        disabled={saving}
        onClick={() => void onSaveAndExit()}
        className={buttonVariants({ variant: "primary", size: "md" })}
      >
        {saving ? "Saving…" : "Save & Exit"}
      </button>
    </div>
  )
}

export default function TradingRulesUnsavedChangesDialog({
  open,
  saving,
  onKeepEditing,
  onDiscard,
  onSaveAndExit,
}: Props) {
  const { isNativeIos } = usePlatformPresentation()
  const body = (
    <p className="text-sm leading-relaxed text-foreground-secondary">
      You have unsaved trading rules. Would you like to save before leaving?
    </p>
  )
  const footer = (
    <Actions
      saving={saving}
      onKeepEditing={onKeepEditing}
      onDiscard={onDiscard}
      onSaveAndExit={onSaveAndExit}
    />
  )

  if (isNativeIos) {
    return (
      <NativeIosPlatformDialog
        open={open}
        onClose={saving ? () => {} : onKeepEditing}
        title="Unsaved Changes"
        closeDisabled={saving}
        showCloseButton={!saving}
        footer={footer}
      >
        {body}
      </NativeIosPlatformDialog>
    )
  }

  return (
    <Modal
      open={open}
      onClose={saving ? () => {} : onKeepEditing}
      closeDisabled={saving}
      title="Unsaved Changes"
      size="sm"
      footer={footer}
    >
      {body}
    </Modal>
  )
}
