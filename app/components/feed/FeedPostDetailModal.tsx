"use client"



import { useCallback, useEffect, useMemo, useRef, useState, type MutableRefObject } from "react"

import DetailModalShell, {

  scrollModalCommentsPane,

} from "@/app/components/ui/DetailModalShell"

import DetailModalImage from "@/app/components/ui/DetailModalImage"

import ImageLightbox from "@/app/components/ui/ImageLightbox"

import { PostInteractionsEngagement } from "@/app/components/PostInteractions"

import TradeCardTimingBlock from "@/app/components/TradeCardTimingBlock"

import { formatEST } from "@/lib/formatEST"

import {

  formatPoints,

  formatRR,

  formatSignedPnlDisplay,

} from "@/lib/formatDisplay"

import FeedCommentsSection from "./FeedCommentsSection"

import FeedPostHeader from "./FeedPostHeader"

import {

  getModeStyles,

  postImageSrc,

  postPublicDescription,

  postTradeJoin,

} from "./feedPostHelpers"

import { formatPublicAccountTypeLabel } from "@/lib/publicAccountPrivacy"

import type { FeedLikeMeta } from "./FeedPostCard"



type FeedPostDetailModalProps = {

  post: any

  user: any

  comments: any[]

  likeMeta: FeedLikeMeta

  commentSubmitting: boolean

  draftSyncRef: MutableRefObject<Record<string, string>>

  openCommentsRef: MutableRefObject<Record<string, boolean>>

  onClose: () => void

  onToggleLike: (post: any) => void

  onSubmitComment: (post: any, text: string) => Promise<boolean>

  onSharePost: (post: any) => void

}



export default function FeedPostDetailModal({

  post,

  user,

  comments,

  likeMeta,

  commentSubmitting,

  draftSyncRef,

  openCommentsRef,

  onClose,

  onToggleLike,

  onSubmitComment,

  onSharePost,

}: FeedPostDetailModalProps) {

  const pid = String(post.id)

  const commentsScrollRef = useRef<HTMLDivElement>(null)

  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null)



  const scrollCommentsIntoView = useCallback(() => {

    requestAnimationFrame(() => {

      scrollModalCommentsPane(commentsScrollRef.current)

    })

  }, [])



  useEffect(() => {

    if (openCommentsRef.current[pid]) {

      scrollCommentsIntoView()

      openCommentsRef.current[pid] = false

    }

  }, [openCommentsRef, pid, scrollCommentsIntoView])



  const modalPostDetails = useMemo(() => {

    const tradeJoin = postTradeJoin(post)

    const pnl = Number(post.pnl)

    const rawAvatar = post.profiles?.avatar_url

    const avatarUrl =

      rawAvatar != null && String(rawAvatar).trim() !== ""

        ? String(rawAvatar).trim()

        : null

    return {

      imageSrc: postImageSrc(post.image_url),

      publicDesc: postPublicDescription(post),

      ticker: tradeJoin?.ticker != null ? String(tradeJoin.ticker) : "—",

      dir: tradeJoin?.direction != null ? String(tradeJoin.direction) : "—",

      acctNorm: (() => {
        const raw = String(tradeJoin?.account_type ?? "").trim().toLowerCase()
        return formatPublicAccountTypeLabel(raw) ?? raw
      })(),
      acctStyleKey: String(tradeJoin?.account_type ?? "").trim().toLowerCase(),

      pnl,

      pnlPositive: !Number.isNaN(pnl) && pnl >= 0,

      points: tradeJoin?.points,

      timingTrade: tradeJoin,

      createdAtLabel: formatEST(post.created_at),

      avatarUrl,

      username: post.profiles?.username || "User",

    }

  }, [post])



  const splitMedia =

    modalPostDetails.imageSrc != null ? (

      <DetailModalImage

        src={modalPostDetails.imageSrc}

        onClick={setLightboxUrl}

      />

    ) : null



  const splitPanel = (

    <>

      <FeedPostHeader

        userId={post.user_id}

        avatarUrl={modalPostDetails.avatarUrl}

        username={modalPostDetails.username}

      />



      <div className="shrink-0 border-b border-white/10 px-4 py-3">

        <PostInteractionsEngagement

          post={post}

          user={user}

          comments={comments}

          likeMeta={likeMeta}

          onToggleLike={onToggleLike}

          onOpenComments={() => scrollCommentsIntoView()}

          onSharePost={onSharePost}

        />

      </div>



      <div className="shrink-0 space-y-3 border-b border-white/10 px-4 py-4 text-sm">

        <div className="flex items-center justify-between gap-3">

          <div className="flex min-w-0 items-center gap-3">

            <div

              className={`shrink-0 text-lg font-semibold tabular-nums ${

                modalPostDetails.pnlPositive

                  ? "text-emerald-400"

                  : "text-red-400"

              }`}

            >

              {formatSignedPnlDisplay(modalPostDetails.pnl)}

            </div>

            <div className="flex min-w-0 items-center gap-2 text-sm font-medium text-white">

              <span className="truncate">

                {modalPostDetails.ticker} • {modalPostDetails.dir}

              </span>

              {modalPostDetails.acctNorm ? (

                <span

                  className={`rounded-full px-2 py-0.5 text-xs ${getModeStyles(modalPostDetails.acctStyleKey)}`}

                >

                  {modalPostDetails.acctNorm}

                </span>

              ) : null}

            </div>

          </div>

          <div className="flex shrink-0 items-center gap-2 text-sm text-gray-300">

            {post.rr != null && post.rr !== "" ? (

              <span className="tabular-nums">RR {formatRR(post.rr)}</span>

            ) : null}

            {modalPostDetails.points !== null &&

            modalPostDetails.points !== undefined ? (

              <span className="rounded-md bg-white/10 px-2 py-0.5 text-gray-200">

                {formatPoints(modalPostDetails.points)} pts

              </span>

            ) : null}

          </div>

        </div>



        {modalPostDetails.publicDesc ? (

          <p className="text-sm leading-relaxed text-white">

            {modalPostDetails.publicDesc}

          </p>

        ) : null}



        {modalPostDetails.timingTrade ? (

          <TradeCardTimingBlock trade={modalPostDetails.timingTrade} />

        ) : null}



        <p className="text-xs text-white/40">

          {modalPostDetails.createdAtLabel}

        </p>

      </div>



      <FeedCommentsSection

        post={post}

        user={user}

        comments={comments}

        commentSubmitting={commentSubmitting}

        draftSyncRef={draftSyncRef}

        listScrollRef={commentsScrollRef}

        onSubmitComment={onSubmitComment}

      />

    </>

  )



  return (

    <>

      <DetailModalShell

        ariaLabel="Post details"

        title="Post"

        layout="split"

        onClose={onClose}

        splitMedia={splitMedia}

        splitPanel={splitPanel}

      />

      <ImageLightbox imageUrl={lightboxUrl} onClose={() => setLightboxUrl(null)} />

    </>

  )

}


