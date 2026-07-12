"use client"

import FeedReelCard from "@/app/components/feed/FeedReelCard"
import { DEMO_USER_ID } from "@/lib/demo/constants"
import { fetchDemoFeedBatch } from "@/lib/demo/demoFeed"
import InstagramAdShell from "./InstagramAdShell"

const noop = () => {}

export default function TradingClipsAdPreview() {
  const { items } = fetchDemoFeedBatch({
    scope: "global",
    userId: DEMO_USER_ID,
    followingIds: [],
    kind: "reel",
    page: 0,
    pageSize: 4,
  })

  const clips = items.slice(0, 2)
  const viewer = { id: DEMO_USER_ID }

  return (
    <InstagramAdShell
      title="Trading Content Built Differently"
      subtitle="Share short-form trading clips, explain setups, and connect every video to the trade behind it."
      settleMs={1000}
    >
      <div className="grid grid-cols-2 gap-4">
        {clips.map((post) => (
          <FeedReelCard
            key={String(post.id)}
            post={post}
            user={viewer}
            likeMeta={{ count: 24, liked: false }}
            comments={[]}
            commentSubmitting={false}
            onSelectPost={noop}
            onOpenComments={noop}
            onToggleLike={noop}
            onSharePost={noop}
            onOpenLinkedTrade={noop}
          />
        ))}
      </div>
    </InstagramAdShell>
  )
}
