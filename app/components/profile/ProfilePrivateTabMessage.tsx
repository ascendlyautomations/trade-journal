export default function ProfilePrivateTabMessage() {
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-6 py-16 text-center">
      <p className="text-2xl text-gray-300" aria-hidden>
        🔒
      </p>
      <p className="mt-3 text-lg font-semibold text-gray-100">
        This profile is private
      </p>
      <p className="mt-2 text-sm text-gray-400">
        Request to follow them to see their content.
      </p>
    </div>
  )
}
