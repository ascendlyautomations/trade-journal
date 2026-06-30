"use client"

import Modal from "@/app/components/ui/Modal"

type PropFirmPassEvalModalProps = {
  open: boolean
  onClose: () => void
  onConfirm: () => void
}

export default function PropFirmPassEvalModal({
  open,
  onClose,
  onConfirm,
}: PropFirmPassEvalModalProps) {
  return (
    <Modal
      open={open}
      onClose={onClose}
      title="Pass Evaluation"
      size="sm"
      footer={
        <div className="flex justify-end gap-3">
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm font-medium text-gray-200 transition hover:bg-white/10"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            className="rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-500"
          >
            Continue
          </button>
        </div>
      }
    >
      <p className="text-sm leading-relaxed text-gray-300">
        Congratulations! Record your passed evaluation and optionally transition
        this account into a funded account.
      </p>
    </Modal>
  )
}
