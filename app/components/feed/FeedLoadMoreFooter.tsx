"use client"

import { memo } from "react"

type FeedLoadMoreFooterProps = {
  loading: boolean
  hasMore: boolean
  onLoadMore: () => void
}

function FeedLoadMoreFooter({ loading, hasMore, onLoadMore }: FeedLoadMoreFooterProps) {
  return (
    <>
      {loading ? (
        <p className="mt-4 text-center text-gray-400">Loading more posts…</p>
      ) : null}

      {hasMore && !loading ? (
        <div className="mt-4 flex justify-center">
          <button
            type="button"
            onClick={() => void onLoadMore()}
            className="rounded bg-blue-500 px-4 py-2 text-white hover:bg-blue-600"
          >
            View More
          </button>
        </div>
      ) : null}
    </>
  )
}

export default memo(FeedLoadMoreFooter)
