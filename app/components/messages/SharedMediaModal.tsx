"use client"

import { useCallback, useEffect, useMemo, useRef, useState } from "react"
import Modal from "@/app/components/ui/Modal"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import StorageImage from "@/app/components/ui/StorageImage"
import {
  fetchConversationSharedMedia,
  SHARED_MEDIA_PAGE_SIZE,
  type ConversationSharedMediaItem,
} from "@/lib/conversationSharedMedia"
type SharedMediaModalProps = {
  open: boolean
  conversationId: string | null
  /** Changes only when the existing message realtime stream receives media. */
  refreshKey?: string | null
  onClose: () => void
}

export default function SharedMediaModal({
  open,
  conversationId,
  refreshKey,
  onClose,
}: SharedMediaModalProps) {
  const [items, setItems] = useState<ConversationSharedMediaItem[]>([])
  const [loading, setLoading] = useState(false)
  const [loadingMore, setLoadingMore] = useState(false)
  const [hasMore, setHasMore] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [failedIds, setFailedIds] = useState<Set<string>>(new Set())
  const [selected, setSelected] =
    useState<ConversationSharedMediaItem | null>(null)
  const lastRefreshKeyRef = useRef<string | null | undefined>(undefined)

  const visibleItems = useMemo(
    () => items.filter((item) => !failedIds.has(item.id)),
    [items, failedIds]
  )

  const load = useCallback(
    async (append: boolean, background = false) => {
      if (!conversationId) return
      if (append) setLoadingMore(true)
      else if (!background) setLoading(true)
      setError(null)

      const last = append ? items[items.length - 1] : null
      const result = await fetchConversationSharedMedia(
        conversationId,
        last ? { createdAt: last.createdAt, id: last.id } : null
      )

      if (append) setLoadingMore(false)
      else if (!background) setLoading(false)
      if (!result.ok) {
        setError("Could not load shared media. Please try again.")
        return
      }

      setHasMore(result.items.length === SHARED_MEDIA_PAGE_SIZE)
      setItems((current) => {
        if (!append) return result.items
        const seen = new Set(current.map((item) => item.id))
        return [
          ...current,
          ...result.items.filter((item) => !seen.has(item.id)),
        ]
      })
    },
    [conversationId, items]
  )

  useEffect(() => {
    if (!open || !conversationId) return
    setItems([])
    setFailedIds(new Set())
    setSelected(null)
    setHasMore(true)
    lastRefreshKeyRef.current = refreshKey
    void load(false)
    // load intentionally resets whenever the modal/conversation opens.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, conversationId])

  useEffect(() => {
    if (!open || !conversationId) return
    if (lastRefreshKeyRef.current === refreshKey) return
    lastRefreshKeyRef.current = refreshKey
    void load(false, true)
    // Existing message realtime drives refreshKey; do not subscribe again here.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, conversationId, refreshKey])

  return (
    <>
      <Modal
        open={open}
        onClose={onClose}
        title="Shared Media"
        size="lg"
        belowNavbar
        panelClassName="max-h-[calc(100vh-5rem)] overflow-hidden"
        bodyClassName="min-h-64"
      >
        {loading ? (
          <div
            className="grid grid-cols-3 gap-2 sm:grid-cols-4 lg:grid-cols-5"
            aria-label="Loading shared media"
          >
            {Array.from({ length: SHARED_MEDIA_PAGE_SIZE }, (_, index) => (
              <div
                key={index}
                className="aspect-square animate-pulse rounded-md bg-white/10"
              />
            ))}
          </div>
        ) : error && items.length === 0 ? (
          <div className="flex min-h-52 flex-col items-center justify-center text-center">
            <p className="text-sm text-gray-300">{error}</p>
            <button
              type="button"
              onClick={() => void load(false)}
              className="mt-4 rounded-lg bg-blue-600 px-4 py-2 text-sm font-medium text-white hover:bg-blue-500"
            >
              Retry
            </button>
          </div>
        ) : visibleItems.length === 0 ? (
          <div className="flex min-h-52 flex-col items-center justify-center text-center">
            <h3 className="text-base font-semibold text-white">
              No shared media yet
            </h3>
            <p className="mt-1 max-w-sm text-sm text-gray-400">
              Images and videos sent in this conversation will appear here.
            </p>
          </div>
        ) : (
          <>
            <div className="grid grid-cols-3 gap-2 sm:grid-cols-4 lg:grid-cols-5">
              {visibleItems.map((item) => (
                <button
                  key={item.id}
                  type="button"
                  onClick={() => setSelected(item)}
                  className="group relative aspect-square min-w-0 overflow-hidden rounded-md bg-white/5 focus:outline-none focus-visible:ring-2 focus-visible:ring-blue-400"
                  aria-label={`Open shared image from ${new Date(
                    item.createdAt
                  ).toLocaleDateString()}`}
                >
                  <StorageImage
                    src={item.imageUrl}
                    originalSrc={item.imageUrl}
                    preset="message-thumb"
                    fallbackToOriginal={false}
                    alt="Shared conversation image"
                    intrinsicWidth={320}
                    intrinsicHeight={320}
                    className="h-full w-full object-cover transition-opacity group-hover:opacity-90"
                    onError={() =>
                      setFailedIds((current) => {
                        const next = new Set(current)
                        next.add(item.id)
                        return next
                      })
                    }
                  />
                </button>
              ))}
            </div>

            <div className="mt-5 flex flex-col items-center gap-2">
              {error ? (
                <p className="text-center text-sm text-red-300">{error}</p>
              ) : null}
              {hasMore ? (
                <button
                  type="button"
                  disabled={loadingMore}
                  onClick={() => void load(true)}
                  className="rounded-lg border border-white/10 bg-white/5 px-4 py-2 text-sm font-medium text-white hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {loadingMore ? "Loading…" : error ? "Retry" : "Load More"}
                </button>
              ) : (
                <p className="text-xs text-gray-500">You’re all caught up.</p>
              )}
            </div>
          </>
        )}
      </Modal>

      <ImageLightbox
        open={selected != null}
        imageUrl={selected?.imageUrl ?? null}
        images={visibleItems.map((item) => item.imageUrl)}
        initialIndex={
          selected
            ? Math.max(
                0,
                visibleItems.findIndex((item) => item.id === selected.id)
              )
            : 0
        }
        alt="Shared conversation image"
        onClose={() => setSelected(null)}
        zIndexClass="z-[10100]"
        belowNavbar
      />
    </>
  )
}
