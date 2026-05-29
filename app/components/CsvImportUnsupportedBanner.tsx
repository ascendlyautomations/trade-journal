"use client"

import Link from "next/link"
import { csvSupportUrl } from "@/lib/csvBrokerHint"

type Props = {
  brokerHint?: string | null
  className?: string
}

export default function CsvImportUnsupportedBanner({ brokerHint, className = "" }: Props) {
  return (
    <div
      className={`rounded-xl border border-amber-500/30 bg-amber-500/10 p-4 text-sm text-amber-50/95 ${className}`}
      role="status"
    >
      <p className="leading-relaxed text-amber-100/90">
        We couldn&apos;t recognize this CSV format.
      </p>
      <p className="mt-2 leading-relaxed text-amber-100/80">
        Help us support your broker/platform by submitting a sample CSV.
      </p>
      <Link
        href={csvSupportUrl(brokerHint)}
        className="mt-4 inline-flex w-full items-center justify-center rounded-xl bg-gradient-to-r from-blue-500 to-teal-400 px-4 py-2.5 text-center font-semibold text-white transition hover:scale-[1.01] sm:w-auto"
      >
        Submit CSV Sample
      </Link>
    </div>
  )
}
