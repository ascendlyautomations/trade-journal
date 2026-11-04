export default function LandingDemoDataBadge({ className = "" }: { className?: string }) {
  return (
    <span
      className={`inline-flex items-center rounded-full border border-white/15 bg-white/5 px-2.5 py-0.5 text-[10px] font-semibold uppercase tracking-[0.12em] text-gray-400 ${className}`.trim()}
    >
      Demo data
    </span>
  )
}
