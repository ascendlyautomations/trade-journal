"use client"

type TradePublicShareToggleProps = {
  isPublic: boolean
  onToggle: () => void
}

export default function TradePublicShareToggle({
  isPublic,
  onToggle,
}: TradePublicShareToggleProps) {
  return (
    <div className="flex items-center justify-between rounded-xl border border-white/10 bg-white/5 p-3">
      <div>
        <p className="text-sm font-medium text-white">Share Publicly</p>
        <p className="text-xs text-white/50">
          {isPublic
            ? "This trade will be visible on your profile and feed."
            : "🔒 Only you can see this trade."}
        </p>
      </div>
      <button
        type="button"
        onClick={onToggle}
        className={`rounded-full border px-4 py-1.5 text-xs font-medium transition ${
          isPublic
            ? "border-blue-400/30 bg-blue-500/20 text-blue-300"
            : "border-white/10 bg-white/10 text-white/50"
        }`}
      >
        {isPublic ? "Public" : "Private"}
      </button>
    </div>
  )
}
