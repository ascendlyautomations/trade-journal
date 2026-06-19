"use client"

type Props = {
  open: boolean
  submitting?: boolean
  onSubmit: () => void
  onTryAnother: () => void
  onCancel: () => void
  overlayClassName?: string
}

const TITLE = "CSV file failed to import"
const BODY =
  "We couldn't read this CSV format yet. You can submit it to TradeTraxs and we'll review it so we can support your broker/export format."

export default function CsvImportFailureModal({
  open,
  submitting = false,
  onSubmit,
  onTryAnother,
  onCancel,
  overlayClassName,
}: Props) {
  if (!open) return null

  return (
    <div
      className={`fixed inset-0 z-[1300] flex items-center justify-center px-4 ${overlayClassName ?? ""}`}
      role="dialog"
      aria-modal="true"
      aria-labelledby="csv-import-failure-title"
    >
      <div className="absolute inset-0 bg-black/60 backdrop-blur-sm" aria-hidden />
      <div className="relative w-full max-w-md rounded-xl border border-amber-500/40 bg-[#0f172a] px-6 py-5 shadow-xl">
        <h3 id="csv-import-failure-title" className="text-base font-semibold text-white">
          {TITLE}
        </h3>
        <p className="mt-3 text-sm leading-relaxed text-amber-100/90">{BODY}</p>
        <div className="mt-5 flex flex-col gap-2">
          <button
            type="button"
            disabled={submitting}
            onClick={onSubmit}
            className="w-full rounded-lg bg-gradient-to-r from-blue-500 to-teal-400 px-4 py-2.5 text-sm font-semibold text-white transition hover:scale-[1.01] disabled:cursor-not-allowed disabled:opacity-60"
          >
            {submitting ? "Submitting..." : "Submit CSV to TradeTraxs"}
          </button>
          <button
            type="button"
            disabled={submitting}
            onClick={onTryAnother}
            className="w-full rounded-lg border border-white/20 bg-white/10 px-4 py-2.5 text-sm font-medium text-white transition hover:bg-white/15 disabled:opacity-60"
          >
            Try another file
          </button>
          <button
            type="button"
            disabled={submitting}
            onClick={onCancel}
            className="w-full rounded-lg px-4 py-2 text-sm text-gray-400 transition hover:text-gray-200 disabled:opacity-60"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  )
}
