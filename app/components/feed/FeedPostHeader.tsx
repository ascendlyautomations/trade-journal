"use client"

import { memo, type ReactNode } from "react"
import Link from "next/link"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import { profilePath } from "@/lib/profileRoutes"
import FeedPostMetaRow from "./FeedPostMetaRow"

type FeedPostHeaderProps = {
  userId: string
  avatarUrl: string | null
  username: string
  /** Content type label (Post, Trade, Reel, …). */
  metaLabel?: string
  metaLabelClassName?: string
  /** Published timestamp — post.created_at. */
  postedAt?: string | null
  metaSuffix?: ReactNode
  /** Custom metadata row (overrides metaLabel/postedAt). */
  meta?: ReactNode
  preview?: boolean
  /** Report / block overflow (non-owner). */
  trailing?: ReactNode
}

function FeedPostHeader({
  userId,
  avatarUrl,
  username,
  metaLabel,
  metaLabelClassName,
  postedAt,
  metaSuffix,
  meta,
  preview = false,
  trailing,
}: FeedPostHeaderProps) {
  const metaRow =
    meta ??
    (metaLabel ? (
      <FeedPostMetaRow
        label={metaLabel}
        labelClassName={metaLabelClassName}
        createdAt={postedAt}
        suffix={metaSuffix}
      />
    ) : null)

  const linkClassName =
    "flex min-w-0 flex-1 cursor-pointer items-center gap-3 px-4 py-2.5 transition-colors" +
    (preview ? "" : " hover:bg-white/5")

  const inner = (
    <>
      <ProfileAvatarImg
        src={avatarUrl}
        className="h-10 w-10 shrink-0 ring-2 ring-white/10"
      />
      <div className="min-w-0 flex-1">
        <p className="truncate text-sm font-semibold text-white md:text-base">
          {username}
        </p>
        {metaRow}
      </div>
    </>
  )

  return (
    <div className="flex items-center border-b border-white/5">
      {preview ? (
        <div className={linkClassName}>{inner}</div>
      ) : (
        <Link
          href={profilePath({ username, id: userId })}
          prefetch={false}
          onClick={(e) => e.stopPropagation()}
          className={linkClassName}
        >
          {inner}
        </Link>
      )}
      {trailing ? (
        <div className="shrink-0 pr-2" onClick={(e) => e.stopPropagation()}>
          {trailing}
        </div>
      ) : null}
    </div>
  )
}

export default memo(FeedPostHeader)
