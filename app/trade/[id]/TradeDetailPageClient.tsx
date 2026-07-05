"use client"

import Link from "next/link"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import FeedPostHeader from "@/app/components/feed/FeedPostHeader"
import FeedPostMetaRow from "@/app/components/feed/FeedPostMetaRow"
import { CommentFocusCompactStrip } from "@/app/components/comments/CommentFocusCompactStrip"
import MobileCommentFocusLayout from "@/app/components/comments/MobileCommentFocusLayout"
import {
  TradeSocialCommentsSection,
  TradeSocialEngagementBar,
  TradeSocialProvider,
} from "../../components/TradeSocialLayer"
import { supabase } from "../../../lib/supabaseClient"
import {
  formatSignedPnlDisplay,
  formatTradePoints,
} from "@/lib/formatDisplay"
import {
  PUBLIC_TRADE_SELECT,
  sanitizeTradeForViewer,
} from "@/lib/publicAccountPrivacy"
import { resolveTradePoints } from "@/lib/resolveTradePoints"
import { profilePath } from "@/lib/profileRoutes"
import { profileSeoDisplayName } from "@/lib/publicSeo"
import { readTradeDetail, writeTradeDetail } from "@/lib/tradeDetailCache"
import TradeCardTimingBlock from "@/app/components/TradeCardTimingBlock"
import ReelViewer from "@/app/components/profile/ReelViewer"
import { fetchTradeReel, type ReelRow } from "@/lib/reels"

function tradeScreenshotSrc(url: string | null | undefined): string | null {
  const raw = url != null ? String(url).trim() : ""
  if (!raw) return null
  if (raw.startsWith("http")) return raw
  const base = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!base) return null
  return `${base}/storage/v1/object/public/screenshots/${raw}`
}

type TradeDetailPageClientProps = {
  tradeId: string
}

export default function TradeDetailPageClient({
  tradeId,
}: TradeDetailPageClientProps) {
  const router = useRouter()

  const cached = readTradeDetail(tradeId)
  const [trade, setTrade] = useState<any>(cached?.trade ?? null)
  const [ownerProfile, setOwnerProfile] = useState(cached?.ownerProfile ?? null)
  const [userId, setUserId] = useState<string | undefined>(cached?.sessionUserId)
  const [loading, setLoading] = useState(!cached)
  const [commentsFocused, setCommentsFocused] = useState(false)
  const [attachedReel, setAttachedReel] = useState<ReelRow | null>(null)
  const [selectedReplay, setSelectedReplay] = useState<ReelRow | null>(null)

  useEffect(() => {
    if (!tradeId) {
      setLoading(false)
      return
    }

    const warm = readTradeDetail(tradeId)
    if (warm) {
      setTrade(warm.trade)
      setOwnerProfile(warm.ownerProfile)
      setUserId(warm.sessionUserId)
      setLoading(false)
      return
    }

    let cancelled = false

    ;(async () => {
      const {
        data: { session },
      } = await supabase.auth.getSession()
      if (cancelled) return
      const sessionUserId = session?.user?.id
      setUserId(sessionUserId)

      const { data, error } = await supabase
        .from("trades")
        .select(PUBLIC_TRADE_SELECT)
        .eq("id", tradeId)
        .maybeSingle()

      if (cancelled) return

      const isOwner =
        sessionUserId != null &&
        data?.user_id != null &&
        String(sessionUserId) === String(data.user_id)
      const resolvedTrade = error
        ? null
        : sanitizeTradeForViewer(data, { isOwner })

      let owner: typeof ownerProfile = null
      if (error && !resolvedTrade) {
        setTrade(null)
        setOwnerProfile(null)
      } else {
        setTrade(resolvedTrade)
        if (resolvedTrade?.user_id) {
          const { data: ownerRow } = await supabase
            .from("profiles")
            .select("id, username, name, avatar_url")
            .eq("id", resolvedTrade.user_id)
            .maybeSingle()
          owner = ownerRow
          if (!cancelled) setOwnerProfile(owner)
        } else if (!cancelled) {
          setOwnerProfile(null)
        }
      }

      writeTradeDetail(tradeId, {
        trade: resolvedTrade,
        ownerProfile: owner,
        sessionUserId,
      })

      if (resolvedTrade?.id) {
        const reel = await fetchTradeReel(supabase, String(resolvedTrade.id))
        if (!cancelled) setAttachedReel(reel)
      } else if (!cancelled) {
        setAttachedReel(null)
      }

      setLoading(false)
    })()

    return () => {
      cancelled = true
    }
  }, [tradeId])

  const imgSrc = trade ? tradeScreenshotSrc(trade.image_url) : null
  const pnl = trade != null ? Number(trade.pnl) : NaN
  const pnlPositive = !Number.isNaN(pnl) && pnl >= 0
  const pnlLabel = Number.isNaN(pnl)
    ? "—"
    : `${pnlPositive ? "+" : "-"}$${Math.abs(pnl)}`
  const resolvedPoints = trade ? resolveTradePoints(trade) : null

  const tradeCompactMeta = trade ? (
    <>
      <span className={pnlPositive ? "text-emerald-400" : "text-red-400"}>
        {pnlLabel}
      </span>
      <span className="text-gray-500"> · </span>
      <span>
        {trade.ticker ?? "—"} · {trade.direction ?? "—"}
      </span>
    </>
  ) : null

  const tradeImage = imgSrc ? (
    <div className="w-full bg-black/30">
      <img
        src={imgSrc}
        alt=""
        loading="lazy"
        decoding="async"
        className="block w-full max-h-[400px] object-cover"
      />
    </div>
  ) : null

  const tradeCollapsibleContent = trade ? (
    <div className="space-y-2">
      {tradeImage ? (
        <div className="hidden md:block">{tradeImage}</div>
      ) : null}
      <div className="space-y-2 p-4">
      <div className="flex items-center justify-between gap-4">
        <div>
          <p className="text-lg font-semibold">{trade.ticker}</p>
          <p className="text-xs text-gray-400">{trade.direction}</p>
        </div>
        <span
          className={`text-sm font-semibold tabular-nums ${
            pnlPositive ? "text-emerald-400" : "text-red-400"
          }`}
        >
          {pnlLabel}
        </span>
      </div>
      {resolvedPoints !== null ? (
        <p className="text-sm text-gray-400">
          Points:{" "}
          <span className="tabular-nums text-gray-200">
            {formatTradePoints(trade)}
          </span>
        </p>
      ) : null}
      {ownerProfile ? (
        <Link
          href={profilePath(ownerProfile)}
          className="inline-flex text-sm font-medium text-blue-300 hover:text-blue-200"
        >
          View {profileSeoDisplayName(ownerProfile)}&apos;s profile →
        </Link>
      ) : null}
      {trade.public_description ? (
        <p className="text-sm leading-relaxed text-gray-300">
          {trade.public_description}
        </p>
      ) : null}
      <TradeCardTimingBlock
        trade={trade}
        onViewReel={
          attachedReel
            ? () => setSelectedReplay(attachedReel)
            : undefined
        }
      />
      </div>
    </div>
  ) : null

  if (!tradeId) {
    return (
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-6 text-white">
          <p className="text-center text-gray-400">Invalid trade link.</p>
        </div>
      </>
    )
  }

  if (loading) {
    return (
      <>
        <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">
          <div>Loading...</div>
        </div>
      </>
    )
  }

  if (!trade) {
    return (
      <>
        <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-6 text-white">
          <div className="mx-auto max-w-xl space-y-4 text-center">
            <p className="text-gray-400">This trade is unavailable.</p>
            <button
              type="button"
              onClick={() => router.push("/trades")}
              className="text-blue-400 hover:underline"
            >
              Back to trades
            </button>
          </div>
        </div>
      </>
    )
  }

  return (
    <>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-6 text-white">
        <div className="mx-auto max-w-xl space-y-4">
          <button
            type="button"
            onClick={() => router.back()}
            className="text-sm text-gray-400 hover:text-white"
          >
            ← Back
          </button>

          <div className="overflow-hidden rounded-xl border border-white/10 bg-white/5">
            <TradeSocialProvider
              tradeId={tradeId}
              currentUserId={userId}
              tradeOwnerUserId={trade.user_id}
              enableRealtime
            >
              <MobileCommentFocusLayout
                commentsFocused={commentsFocused}
                header={
                  ownerProfile ? (
                    <FeedPostHeader
                      userId={String(ownerProfile.id)}
                      avatarUrl={ownerProfile.avatar_url ?? null}
                      username={
                        ownerProfile.username ||
                        ownerProfile.name ||
                        "User"
                      }
                      metaLabel="Trade"
                      metaLabelClassName="font-medium text-amber-400/90"
                      postedAt={trade.created_at}
                    />
                  ) : undefined
                }
                compactHeader={
                  ownerProfile ? (
                    <CommentFocusCompactStrip
                      userId={ownerProfile.id}
                      username={ownerProfile.username}
                      avatarUrl={ownerProfile.avatar_url}
                      meta={
                        <>
                          <FeedPostMetaRow
                            label="Trade"
                            labelClassName="font-medium text-amber-400/90"
                            createdAt={trade.created_at}
                          />
                          <div className="mt-0.5 truncate text-xs font-medium text-gray-300">
                            {tradeCompactMeta}
                          </div>
                        </>
                      }
                      onExpand={() => setCommentsFocused(false)}
                    />
                  ) : undefined
                }
                mobileMedia={tradeImage ?? undefined}
                engagement={
                  <TradeSocialEngagementBar
                    className="px-4 py-2"
                    onCommentsFocus={() => setCommentsFocused(true)}
                  />
                }
                engagementClassName="shrink-0 border-t border-white/10"
                engagementAfterCollapsible
                collapsibleContent={tradeCollapsibleContent}
                comments={
                  <TradeSocialCommentsSection className="border-t border-white/10 px-4 pb-4" />
                }
              />
            </TradeSocialProvider>
          </div>
        </div>
      </div>

      <ReelViewer
        reel={selectedReplay}
        creator={
          ownerProfile
            ? {
                username: ownerProfile.username,
                avatar_url: ownerProfile.avatar_url,
                name: ownerProfile.name,
              }
            : null
        }
        onClose={() => setSelectedReplay(null)}
      />
    </>
  )
}
