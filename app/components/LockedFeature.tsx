import Link from "next/link"

type LockedFeatureProps = {
  title: string
  className?: string
}

export default function LockedFeature({ title, className = "" }: LockedFeatureProps) {
  return (
    <div
      className={`flex min-h-[220px] h-full w-full flex-col items-center justify-center rounded-xl border border-white/10 bg-[#0b1f3a] p-6 text-center ${className}`}
    >
      <h3 className="mb-2 text-lg font-semibold text-white">
        🔒 {title}
      </h3>
      <p className="mb-4 max-w-sm text-sm text-gray-400">
        Upgrade to Pro to unlock this feature
      </p>
      <Link
        href="/pricing"
        className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
      >
        Upgrade to Pro
      </Link>
    </div>
  )
}
