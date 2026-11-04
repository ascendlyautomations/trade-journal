"use client"

import { useMemo } from "react"
import AchievementCard from "@/app/components/AchievementCard"
import FeedPostActions from "@/app/components/feed/FeedPostActions"
import FeedPostBody from "@/app/components/feed/FeedPostBody"
import FeedPostHeader from "@/app/components/feed/FeedPostHeader"
import FeedPostScreenshot from "@/app/components/feed/FeedPostScreenshot"
import {
  formatPublicAccountTypeLabel,
} from "@/lib/publicAccountPrivacy"
import { achievementFromPost } from "@/lib/achievementPostEngagement"
import { DEMO_USER_ID } from "@/lib/demo/constants"
import {
  DEMO_FEED_COMMENTS,
  DEMO_FEED_LIKES,
  findDemoFeedItem,
} from "@/lib/demo/demoFeed"
import {
  getModeStyles,
  normalizeFeedAccountType,
  postImageSrc,
  postPublicDescription,
  postTradeJoin,
} from "@/app/components/feed/feedPostHelpers"
import { isCopyTradedMode } from "@/lib/tradeMode"
import LandingDemoDataBadge from "./LandingDemoDataBadge"

const noop = () => {}

const VIEWER = { id: DEMO_USER_ID }

/** Distinct demo identities — illustrative only. */
const HERO_SOCIAL_POST_IDS = {
  trade: "demo-post-4",
  achievement: "demo-achievement-2",
  profile: "demo-profile-1",
} as const

function demoLikeMeta(postId: string) {
  return DEMO_FEED_LIKES[postId] ?? { count: 0, liked: false }
}

function feedCardShell(className: string) {
  return `tt-hero-social-tile overflow-hidden rounded-xl border border-white/10 bg-white/[0.06] shadow-lg shadow-black/25 backdrop-blur-sm ${className}`.trim()
}

function HeroMarketingTradeCard({ post }: { post: Record<string, unknown> }) {
  const postId = String(post.id)
  const avatarUrl = useMemo(() => {
    const raw = (post.profiles as { avatar_url?: unknown })?.avatar_url
    if (raw == null) return null
    const trimmed = String(raw).trim()
    return trimmed !== "" ? trimmed : null
  }, [post.profiles])
  const username = String((post.profiles as { username?: string })?.username ?? "User")
  const tradeRow = useMemo(() => postTradeJoin(post), [post])
  const imageSrc = useMemo(
    () => postImageSrc(post.image_url as string | null | undefined),
    [post.image_url]
  )
  const publicDesc = useMemo(() => postPublicDescription(post), [post])
  const pnl = Number(post.pnl)
  const pnlPositive = !Number.isNaN(pnl) && pnl >= 0
  const isCopyTrade = isCopyTradedMode(tradeRow)
  const tradeDisplay = useMemo(() => {
    const accountTypeRaw = normalizeFeedAccountType(
      tradeRow?.account_type ?? tradeRow?.mode
    )
    const accountTypeLabel =
      formatPublicAccountTypeLabel(accountTypeRaw) ?? accountTypeRaw
    return {
      tickerLabel: tradeRow?.ticker != null ? String(tradeRow.ticker) : "-",
      dirLabel: tradeRow?.direction != null ? String(tradeRow.direction) : "-",
      accountTypeNorm: isCopyTrade ? "" : accountTypeLabel,
      accountTypeStyles: accountTypeRaw ? getModeStyles(accountTypeRaw) : "",
    }
  }, [tradeRow, isCopyTrade])
  const comments = DEMO_FEED_COMMENTS[postId] ?? []

  return (
    <article className={feedCardShell("tt-hero-social-tile--trade tt-phase1-dark")}>
      <FeedPostHeader
        userId={String(post.user_id)}
        avatarUrl={avatarUrl}
        username={username}
        metaLabel="Trade"
        metaLabelClassName="font-medium text-amber-400/90"
        postedAt={String(post.created_at)}
        preview
      />
      {imageSrc ? (
        <FeedPostScreenshot
          imageSrc={imageSrc}
          fixedFrameClassName="tt-hero-trade-thumb"
          priority
        />
      ) : null}
      <FeedPostActions
        post={post}
        user={VIEWER}
        commentCount={comments.length}
        likeMeta={demoLikeMeta(postId)}
        onToggleLike={noop}
        onOpenComments={noop}
        onSharePost={noop}
      />
      <FeedPostBody
        pnl={pnl}
        pnlPositive={pnlPositive}
        tickerLabel={tradeDisplay.tickerLabel}
        dirLabel={tradeDisplay.dirLabel}
        accountTypeNorm={tradeDisplay.accountTypeNorm}
        accountTypeStyles={tradeDisplay.accountTypeStyles}
        rr={post.rr}
        publicDesc={publicDesc}
        timingTrade={tradeRow}
      />
    </article>
  )
}

function HeroMarketingAchievementCard({ post }: { post: Record<string, unknown> }) {
  const postId = String(post.id)
  const achievement = useMemo(() => achievementFromPost(post), [post])
  const avatarUrl = useMemo(() => {
    const raw = (post.profiles as { avatar_url?: unknown })?.avatar_url
    if (raw == null) return null
    const trimmed = String(raw).trim()
    return trimmed !== "" ? trimmed : null
  }, [post.profiles])
  const username = String((post.profiles as { username?: string })?.username ?? "User")
  const comments = DEMO_FEED_COMMENTS[postId] ?? []

  return (
    <article
      className={feedCardShell("tt-hero-social-tile--achievement tt-phase1-dark")}
    >
      <FeedPostHeader
        userId={String(post.user_id)}
        avatarUrl={avatarUrl}
        username={username}
        metaLabel="Achievement"
        metaLabelClassName="font-medium text-amber-400/90"
        postedAt={String(post.created_at)}
        preview
      />
      <div className="px-3 pb-1 pt-2 md:px-4">
        <AchievementCard
          achievement={achievement}
          showVisibility={false}
          mediaContext="feed"
          mediaPriority={false}
        />
      </div>
      <FeedPostActions
        post={post}
        user={VIEWER}
        commentCount={comments.length}
        likeMeta={demoLikeMeta(postId)}
        onToggleLike={noop}
        onOpenComments={noop}
        onSharePost={noop}
      />
    </article>
  )
}

function HeroMarketingProfileCard({ post }: { post: Record<string, unknown> }) {
  const postId = String(post.id)
  const avatarUrl = useMemo(() => {
    const raw = (post.profiles as { avatar_url?: unknown })?.avatar_url
    if (raw == null) return null
    const trimmed = String(raw).trim()
    return trimmed !== "" ? trimmed : null
  }, [post.profiles])
  const username = String((post.profiles as { username?: string })?.username ?? "User")
  const content = useMemo(() => {
    const raw = post.content != null ? String(post.content).trim() : ""
    return raw !== "" ? raw : null
  }, [post.content])
  const comments = DEMO_FEED_COMMENTS[postId] ?? []

  return (
    <article className={feedCardShell("tt-hero-social-tile--profile tt-phase1-dark")}>
      <FeedPostHeader
        userId={String(post.user_id)}
        avatarUrl={avatarUrl}
        username={username}
        metaLabel="Post"
        postedAt={String(post.created_at)}
        preview
      />
      <FeedPostActions
        post={post}
        user={VIEWER}
        commentCount={comments.length}
        likeMeta={demoLikeMeta(postId)}
        onToggleLike={noop}
        onOpenComments={noop}
        onSharePost={noop}
      />
      {content ? (
        <div className="px-4 pb-3 pt-0 max-md:px-3">
          <p className="line-clamp-4 whitespace-pre-wrap break-words [overflow-wrap:anywhere] text-sm leading-relaxed text-white">
            {content}
          </p>
        </div>
      ) : null}
    </article>
  )
}

export default function LandingHeroSocialComposition() {
  const tradePost = findDemoFeedItem(HERO_SOCIAL_POST_IDS.trade, "trade")
  const achievementPost = findDemoFeedItem(HERO_SOCIAL_POST_IDS.achievement, "achievement")
  const profilePost = findDemoFeedItem(HERO_SOCIAL_POST_IDS.profile, "profile")

  if (!tradePost) return null

  return (
    <div className="tt-hero-social-mosaic-wrap">
      <div className="tt-hero-social-mosaic pointer-events-none select-none">
        <HeroMarketingTradeCard post={tradePost as Record<string, unknown>} />
        {achievementPost ? (
          <HeroMarketingAchievementCard
            post={achievementPost as Record<string, unknown>}
          />
        ) : null}
        {profilePost ? (
          <HeroMarketingProfileCard post={profilePost as Record<string, unknown>} />
        ) : null}
      </div>
      <div className="tt-hero-social-demo-foot">
        <LandingDemoDataBadge />
        <p className="tt-hero-social-demo-caption">
          Illustrative demo traders and posts, not real members or testimonials.
        </p>
      </div>
    </div>
  )
}
