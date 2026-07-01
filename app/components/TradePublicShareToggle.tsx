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
        <p className="text-sm font-medium text-white">Share to Community</p>
        <p className="text-xs text-white/50">
          {isPublic
            ? "🌎 This trade will be shared to your profile and feed."
            : "🔒 Only you can see this trade."}
        </p>
      </div>
      <button
        type="button"
        onClick={onToggle}
        className={`rounded-full border px-4 py-1.5 text-xs font-medium transition ${
          isPublic
            ? "border-green-400/30 bg-green-500/20 text-green-400"
            : "border-white/10 bg-white/10 text-white/50"
        }`}
      >
        {isPublic ? "Public" : "Private"}
      </button>
    </div>
  )
}
