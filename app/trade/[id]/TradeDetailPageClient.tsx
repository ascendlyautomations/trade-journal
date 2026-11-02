"use client"

import Link from "next/link"
import dynamic from "next/dynamic"
import { useCallback, useEffect, useState } from "react"
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
import { asJsonObject } from "@/lib/supabaseProjectedQuery"
import {
  formatRR,
  formatSignedPnlDisplay,
} from "@/lib/formatDisplay"
import { hasStoredRr } from "@/lib/tradeRr"
import {
  sanitizeTradeForViewer,
  tradeRelationForViewer,
  tradeSelectForViewer,
} from "@/lib/publicAccountPrivacy"
import { rpcTradeOwnerReadResult } from "@/lib/tradeOwnerRead"
import { hasStoredTradePoints } from "@/lib/resolveTradePoints"
import {
  computeActualPoints,
  formatSignedPoints,
  resolveRealizedRr,
} from "@/lib/tradePointsAndRealizedRr"
import ContentMediaPreview from "@/app/components/ContentMediaPreview"
import ImageLightbox from "@/app/components/ui/ImageLightbox"
import TradeCopyTradingDetails from "@/app/components/trade/TradeCopyTradingDetails"
import CopyTradedBadge from "@/app/components/trade/CopyTradedBadge"
import { isCopyTradedTrade } from "@/lib/tradeCopyTrading"
import { ACCOUNTS_SELECT } from "@/lib/appDataCache"
import { profilePath } from "@/lib/profileRoutes"
import { profileSeoDisplayName } from "@/lib/publicSeo"
import { readTradeDetail, writeTradeDetail } from "@/lib/tradeDetailCache"
import TradeCardTimingBlock from "@/app/components/TradeCardTimingBlock"
import ExpandableText from "@/app/components/ui/ExpandableText"
import ReelViewer from "@/app/components/profile/ReelViewer"
import { fetchTradeReel, type ReelRow } from "@/lib/reels"
import {
  DesktopWebViewport,
  MobileWebViewport,
} from "@/app/components/mobile/MobileWebViewport"
import MobileWebTradeDetailSurface from "@/app/components/mobile/trade/MobileWebTradeDetailSurface"
import {
  MOBILE_WEB_NEUTRAL_PAGE_BG,
  MOBILE_WEB_PAGE_PAD,
} from "@/lib/mobileWebPageSurface"
import { ConfirmModal, useDeleteTradeConfirmation } from "@/app/components/ui"
import { deleteUserTrade } from "@/lib/deleteTrade"
import { isDemoModeActive } from "@/lib/demo/demoMode"
import { requestDemoSignup } from "@/lib/demo/requestDemoSignup"
import { DEMO_USER_ID } from "@/lib/demo/constants"
import { DEMO_ACCOUNTS, DEMO_PROFILE, DEMO_TRADES } from "@/lib/demo/fixtures"
import { tradeAnalysisHref } from "@/lib/tradeAnalysisNavigation"
import { setMobileWebTradeTitle } from "@/lib/mobileWebTradeTitle"
import { useIsNativeIos } from "@/lib/useIsNativeIos"

const InputTradeForm = dynamic(
  () => import("@/app/components/InputTradeForm"),
  { ssr: false }
)
const ShareToConversationsModal = dynamic(
  () => import("@/app/components/ShareToConversationsModal"),
  { ssr: false }
)

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
  const isNativeIos = useIsNativeIos()

  const cached = readTradeDetail(tradeId)
  const [trade, setTrade] = useState<any>(cached?.trade ?? null)
  const [ownerProfile, setOwnerProfile] = useState(cached?.ownerProfile ?? null)
  const [userId, setUserId] = useState<string | undefined>(cached?.sessionUserId)
  const [loading, setLoading] = useState(!cached)
  const [commentsFocused, setCommentsFocused] = useState(false)
  const [attachedReel, setAttachedReel] = useState<ReelRow | null>(null)
  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null)
  const [selectedReplay, setSelectedReplay] = useState<ReelRow | null>(null)
  const [ownerAccounts, setOwnerAccounts] = useState<any[]>([])
  const [editingTrade, setEditingTrade] = useState<any | null>(null)
  const [sendTradeId, setSendTradeId] = useState<string | null>(null)
  const [reloadNonce, setReloadNonce] = useState(0)

  useEffect(() => {
    if (!tradeId) {
      setLoading(false)
      return
    }

    const warm = reloadNonce === 0 ? readTradeDetail(tradeId) : null
    if (warm?.trade) {
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

      const isOwner =
        sessionUserId != null &&
        (
          await supabase
            .from("trades")
            .select("user_id")
            .eq("id", tradeId)
            .eq("user_id", sessionUserId)
            .maybeSingle()
        ).data != null

      let tradeRow: Record<string, unknown> | null = null
      let loadError: unknown = null
      if (isOwner) {
        const ownerRead = await rpcTradeOwnerReadResult(supabase, tradeId)
        if (ownerRead.ok) {
          tradeRow = ownerRead.row
        } else {
          loadError =
            ownerRead.reason === "not_found"
              ? null
              : new Error(ownerRead.message)
        }
      } else {
        const { data, error } = await supabase
          .from(tradeRelationForViewer(false))
          .select(tradeSelectForViewer(false))
          .eq("id", tradeId)
          .maybeSingle()
          .overrideTypes<Record<string, unknown> | null, { merge: false }>()
        loadError = error
        tradeRow = asJsonObject(error ? null : data)
      }

      if (cancelled) return
      let resolvedTrade = tradeRow
        ? sanitizeTradeForViewer(tradeRow, { isOwner })
        : null
      let demoOwner = false
      if (!resolvedTrade && isDemoModeActive()) {
        const demoTrade = DEMO_TRADES.find(
          (row) => String(row.id) === String(tradeId)
        )
        if (demoTrade) {
          resolvedTrade = demoTrade
          demoOwner = true
          setUserId(DEMO_USER_ID)
        }
      }

      let owner: typeof ownerProfile = null
      if (loadError && !resolvedTrade) {
        setTrade(null)
        setOwnerProfile(null)
      } else {
        setTrade(resolvedTrade)
        if (demoOwner) {
          owner = DEMO_PROFILE
          if (!cancelled) setOwnerProfile(DEMO_PROFILE)
        } else if (resolvedTrade?.user_id) {
          const ownerId = String(resolvedTrade.user_id)
          const { data: ownerRow } = await supabase
            .from("profiles")
            .select("id, username, name, avatar_url")
            .eq("id", ownerId)
            .maybeSingle()
          owner = ownerRow
          if (!cancelled) setOwnerProfile(owner)
        } else if (!cancelled) {
          setOwnerProfile(null)
        }
      }

      if (demoOwner) {
        if (!cancelled) {
          setOwnerAccounts(
            DEMO_ACCOUNTS.map((row) => ({
              ...row,
              size: row.account_size,
            }))
          )
        }
      } else if (isOwner && sessionUserId) {
        const { data: accountRows } = await supabase
          .from("accounts")
          .select(ACCOUNTS_SELECT)
          .eq("user_id", sessionUserId)
        if (!cancelled) {
          setOwnerAccounts(
            (accountRows ?? []).map((row) => ({
              ...row,
              size: row.account_size,
            }))
          )
        }
      }

      if (resolvedTrade) {
        writeTradeDetail(tradeId, {
          trade: resolvedTrade,
          ownerProfile: owner ?? (demoOwner ? DEMO_PROFILE : null),
          sessionUserId: demoOwner ? DEMO_USER_ID : sessionUserId,
        })
      }

      if (resolvedTrade?.id && !demoOwner) {
        try {
          const reel = await fetchTradeReel(supabase, String(resolvedTrade.id))
          if (!cancelled) setAttachedReel(reel)
        } catch {
          if (!cancelled) setAttachedReel(null)
        }
      } else if (!cancelled) {
        setAttachedReel(null)
      }

      setLoading(false)
    })()

    return () => {
      cancelled = true
    }
  }, [tradeId, reloadNonce])

  const isOwner = Boolean(
    userId && trade?.user_id && String(trade.user_id) === userId
  )

  useEffect(() => {
    if (isNativeIos) return
    const ticker = String(trade?.ticker ?? "").trim()
    setMobileWebTradeTitle(ticker || "Trade")
    return () => setMobileWebTradeTitle(null)
  }, [isNativeIos, trade?.ticker])

  const performDeleteTrade = useCallback(
    async (id: string) => {
      if (isDemoModeActive()) {
        requestDemoSignup("delete")
        return
      }
      await deleteUserTrade(supabase, id, { userId })
      router.push("/trades")
    },
    [router, userId]
  )
  const { requestDelete: handleDeleteTrade, confirmModalProps } =
    useDeleteTradeConfirmation(performDeleteTrade)

  const imgSrc = trade ? tradeScreenshotSrc(trade.image_url) : null
  const pnl = trade != null ? Number(trade.pnl) : NaN
  const pnlPositive = !Number.isNaN(pnl) && pnl >= 0
  const pnlLabel = Number.isNaN(pnl)
    ? "—"
    : `${pnlPositive ? "+" : "-"}$${Math.abs(pnl)}`
  const pointsTargeted =
    trade && hasStoredTradePoints(trade.points) ? Number(trade.points) : null
  const actualPoints = trade ? computeActualPoints(trade) : null
  const realizedRr = trade ? resolveRealizedRr(trade) : null

  const tradeCompactMeta = trade ? (
    <>
      <span className={pnlPositive ? "text-emerald-400" : "text-red-400"}>
        {pnlLabel}
      </span>
      <span className="text-gray-400"> · </span>
      <span>
        {trade.ticker ?? "—"} · {trade.direction ?? "—"}
      </span>
    </>
  ) : null

  const tradeImage = imgSrc ? (
    <ContentMediaPreview
      src={imgSrc}
      preset="feed-detail"
      displayMode={trade?.image_display_mode as string | null | undefined}
      imageCrop={trade?.image_crop}
      onClick={setLightboxUrl}
    />
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
          {isCopyTradedTrade(trade) ? (
            <div className="mt-1">
              <CopyTradedBadge trade={trade} />
            </div>
          ) : null}
        </div>
        <span
          className={`text-sm font-semibold tabular-nums ${
            pnlPositive ? "text-emerald-400" : "text-red-400"
          }`}
        >
          {pnlLabel}
        </span>
      </div>
      {pointsTargeted !== null ? (
        <p className="text-sm text-gray-400">
          Points Targeted:{" "}
          <span className="tabular-nums text-gray-200">
            {formatSignedPoints(pointsTargeted)}
          </span>
        </p>
      ) : null}
      <p className="text-sm text-gray-400">
        Actual Points:{" "}
        <span className="tabular-nums text-gray-200">
          {formatSignedPoints(actualPoints)}
        </span>
      </p>
      <p className="text-sm text-gray-400">
        Realized R:R:{" "}
        <span className="tabular-nums text-gray-200">
          {realizedRr != null ? formatRR(realizedRr) : "—"}
        </span>
      </p>
      {hasStoredRr((trade as { max_rr_reached?: unknown }).max_rr_reached) ? (
        <p className="text-sm text-gray-400">
          Max R:R Reached:{" "}
          <span className="tabular-nums text-gray-200">
            {formatRR((trade as { max_rr_reached?: unknown }).max_rr_reached)}
          </span>
        </p>
      ) : null}
      <TradeCopyTradingDetails
        trade={trade}
        accounts={ownerAccounts}
        className="mt-2"
      />
      {ownerProfile ? (
        <Link
          href={profilePath(ownerProfile)}
          className="inline-flex text-sm font-medium text-blue-300 hover:text-blue-200"
        >
          View {profileSeoDisplayName(ownerProfile)}&apos;s profile →
        </Link>
      ) : null}
      {trade.public_description ? (
        <ExpandableText
          className="text-sm leading-relaxed text-gray-300"
          textClassName="text-gray-300"
        >
          {trade.public_description}
        </ExpandableText>
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

  const pageShellClass = `min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white ${MOBILE_WEB_NEUTRAL_PAGE_BG}`

  if (!tradeId) {
    return (
      <>
        <div className={`${pageShellClass} p-6 ${MOBILE_WEB_PAGE_PAD}`}>
          <p className="text-center text-gray-400">Invalid trade link.</p>
        </div>
      </>
    )
  }

  if (loading) {
    return (
      <>
        <div className={`flex items-center justify-center ${pageShellClass}`}>
          <div>Loading trade…</div>
        </div>
      </>
    )
  }

  if (!trade) {
    return (
      <>
        <div className={`${pageShellClass} p-6 ${MOBILE_WEB_PAGE_PAD}`}>
          <div className="mx-auto max-w-xl space-y-4 text-center">
            <p className="text-gray-400">This trade is unavailable.</p>
            <button
              type="button"
              onClick={() => router.push("/trades")}
              className="text-blue-400 hover:underline max-md:hidden"
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
      <MobileWebViewport>
        <div className={`${pageShellClass} ${MOBILE_WEB_PAGE_PAD}`}>
          <MobileWebTradeDetailSurface
            trade={trade}
            tradeId={tradeId}
            userId={userId}
            ownerProfile={ownerProfile}
            ownerAccounts={ownerAccounts}
            imgSrc={imgSrc}
            attachedReel={attachedReel}
            onOpenLightbox={setLightboxUrl}
            onViewReel={() => {
              if (attachedReel) setSelectedReplay(attachedReel)
            }}
            onEdit={
              isOwner
                ? () => {
                    if (isDemoModeActive()) {
                      requestDemoSignup("edit")
                      return
                    }
                    setEditingTrade({ ...trade })
                  }
                : undefined
            }
            onDelete={
              isOwner ? () => handleDeleteTrade(tradeId) : undefined
            }
            onShare={
              isOwner
                ? () => {
                    if (isDemoModeActive()) {
                      requestDemoSignup("trade")
                      return
                    }
                    setSendTradeId(tradeId)
                  }
                : undefined
            }
            onCopyLink={() => {
              const url = `${window.location.origin}/trade/${tradeId}`
              void navigator.clipboard?.writeText(url)
            }}
            onAnalyze={
              isOwner
                ? () => {
                    if (isDemoModeActive()) {
                      requestDemoSignup("ai")
                      return
                    }
                    router.push(tradeAnalysisHref(tradeId))
                  }
                : undefined
            }
          />
        </div>
      </MobileWebViewport>
      <DesktopWebViewport>
      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-6 text-white">
        <div className="mx-auto max-w-xl space-y-4">
          <button
            type="button"
            onClick={() => router.back()}
            className="text-sm text-gray-400 hover:text-white max-md:hidden"
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
                    className="px-4 py-1"
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
      </DesktopWebViewport>

      {editingTrade ? (
        <InputTradeForm
          key={String(editingTrade.id)}
          existingTrade={editingTrade}
          onClose={() => setEditingTrade(null)}
          onSave={() => {
            setEditingTrade(null)
            setReloadNonce((n) => n + 1)
            router.refresh()
          }}
        />
      ) : null}
      {sendTradeId ? (
        <ShareToConversationsModal
          key={sendTradeId}
          open
          onClose={() => setSendTradeId(null)}
          title="Send trade"
          tradeId={sendTradeId}
        />
      ) : null}
      <ConfirmModal {...confirmModalProps} />

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
      <ImageLightbox
        imageUrl={lightboxUrl}
        onClose={() => setLightboxUrl(null)}
      />
    </>
  )
}
