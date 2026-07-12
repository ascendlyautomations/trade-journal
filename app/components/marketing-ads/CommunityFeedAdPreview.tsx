"use client"

import FeedPostCard from "@/app/components/feed/FeedPostCard"
import FeedAchievementPostCard from "@/app/components/feed/FeedAchievementPostCard"
import { DEMO_USER_ID } from "@/lib/demo/constants"
import { fetchDemoFeedBatch } from "@/lib/demo/demoFeed"
import InstagramAdShell from "./InstagramAdShell"

const noop = () => {}
const asyncNoop = async () => false

export default function CommunityFeedAdPreview() {
  const tradeBatch = fetchDemoFeedBatch({
    scope: "global",
    userId: DEMO_USER_ID,
    followingIds: [],
    kind: "trade",
    page: 0,
    pageSize: 3,
  })
  const achievementBatch = fetchDemoFeedBatch({
    scope: "global",
    userId: DEMO_USER_ID,
    followingIds: [],
    kind: "achievement",
    page: 0,
    pageSize: 2,
  })

  const tradePosts = tradeBatch.items.slice(0, 2)
  const achievement = achievementBatch.items[0]
  const viewer = { id: DEMO_USER_ID }

  return (
    <InstagramAdShell
      title="Built for Traders"
      subtitle="Share trades, clips, posts, achievements, and progress with a community that understands trading."
      settleMs={1000}
    >
      <div className="mx-auto max-w-[640px] space-y-4">
        {tradePosts.map((post, index) => (
          <FeedPostCard
            key={String(post.id)}
            post={post}
            user={viewer}
            likeMeta={{ count: 18 + index * 7, liked: index === 0 }}
            comments={[]}
            commentSubmitting={false}
            preview
            onSelectPost={noop}
            onOpenComments={noop}
            onToggleLike={noop}
            onSubmitComment={asyncNoop}
            onSharePost={noop}
          />
        ))}
        {achievement ? (
          <FeedAchievementPostCard
            post={achievement}
            user={viewer}
            likeMeta={{ count: 42, liked: false }}
            comments={[]}
            commentSubmitting={false}
            onSelectPost={noop}
            onOpenComments={noop}
            onToggleLike={noop}
            onSharePost={noop}
          />
        ) : null}
      </div>
    </InstagramAdShell>
  )
}
