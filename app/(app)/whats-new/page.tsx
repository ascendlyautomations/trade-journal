"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import {
  fetchPublishedPlatformUpdates,
  type PlatformUpdatePublic,
} from "@/lib/platformUpdatesClient"
import {
  PLATFORM_UPDATE_CATEGORY_LABELS,
  type PlatformUpdateCategoryId,
} from "@/lib/platformUpdateDestinations"

export default function WhatsNewPage() {
  const [updates, setUpdates] = useState<PlatformUpdatePublic[]>([])
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    ;(async () => {
      try {
        const rows = await fetchPublishedPlatformUpdates()
        if (!cancelled) setUpdates(rows)
      } catch (e) {
        if (!cancelled) setError(e instanceof Error ? e.message : "Failed to load")
      } finally {
        if (!cancelled) setLoading(false)
      }
    })()
    return () => {
      cancelled = true
    }
  }, [])

  return (
    <div className="mx-auto max-w-2xl space-y-6 p-4 md:p-8">
      <div>
        <h1 className="text-2xl font-bold text-white">What&apos;s New</h1>
        <p className="mt-1 text-sm text-gray-400">
          Product updates and announcements from TradeTraxs.
        </p>
      </div>

      {loading && <p className="text-sm text-gray-400">Loading…</p>}
      {error && <p className="text-sm text-red-300">{error}</p>}

      {!loading && !error && updates.length === 0 && (
        <p className="text-sm text-gray-400">No updates yet.</p>
      )}

      <ul className="space-y-4">
        {updates.map((u) => (
          <li
            key={u.id}
            className="rounded-xl border border-white/10 bg-white/5 p-4"
          >
            <div className="flex flex-wrap items-center gap-2 text-xs uppercase tracking-wide text-blue-300">
              {PLATFORM_UPDATE_CATEGORY_LABELS[u.category as PlatformUpdateCategoryId]}
              {u.publishedAt && (
                <span className="text-gray-500 normal-case">
                  {new Date(u.publishedAt).toLocaleString()}
                </span>
              )}
            </div>
            <h2 className="mt-2 text-lg font-semibold text-white">{u.title}</h2>
            <p className="mt-2 whitespace-pre-wrap text-sm text-gray-200">{u.body}</p>
            {u.href && (
              <Link
                href={u.href}
                className="mt-3 inline-block text-sm font-medium text-emerald-400 hover:underline"
              >
                Open in TradeTraxs →
              </Link>
            )}
          </li>
        ))}
      </ul>
    </div>
  )
}
