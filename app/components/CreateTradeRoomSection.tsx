"use client"

type CreateTradeRoomSectionProps = {
  onCreate: () => void
  creating?: boolean
  disabled?: boolean
}

export default function CreateTradeRoomSection({
  onCreate,
  creating = false,
  disabled = false,
}: CreateTradeRoomSectionProps) {
  return (
    <section className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
      <h2 className="text-xl font-semibold text-white">Create Trade Room</h2>
      <p className="mt-2 text-sm leading-relaxed text-gray-400">
        Build your own community, chat with traders, share trades, and grow
        together.
      </p>

      <div className="mt-6 space-y-4">
        <div className="rounded-xl border border-blue-400/20 bg-blue-500/10 p-4">
          <p className="text-sm leading-relaxed text-blue-100/90">
            Your Trade Room gets default channels, an invite link, and optional
            profile visibility. You can customize everything after creation.
          </p>
        </div>

        <button
          type="button"
          onClick={onCreate}
          disabled={disabled || creating}
          className="w-full rounded-xl bg-blue-500 py-3 text-sm font-semibold text-white transition hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-60 disabled:hover:bg-blue-500"
        >
          {creating ? "Creating…" : "Create Your Own Trade Room"}
        </button>
      </div>
    </section>
  )
}
