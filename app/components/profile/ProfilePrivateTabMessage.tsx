const copy = {
  trades: "This trader has chosen to keep their trades private.",
  reels: "Clips are only visible to approved followers.",
  posts: "Posts are only visible to approved followers.",
} as const

export default function ProfilePrivateTabMessage({
  variant,
}: {
  variant: keyof typeof copy
}) {
  return (
    <div className="rounded-xl border border-white/10 bg-white/5 p-6 py-16 text-center">
      <p className="text-lg text-gray-100">🔒 Private Profile</p>
      <p className="mt-2 text-sm text-gray-400">{copy[variant]}</p>
      <p className="mt-2 text-sm text-gray-400">
        Follow this trader to request access.
      </p>
    </div>
  )
}
