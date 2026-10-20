"use client"

import { useCallback, useMemo } from "react"
import ContentOverflowMenu from "@/app/components/moderation/ContentOverflowMenu"
import { useOptionalContentModeration } from "@/app/components/moderation/ContentModerationProvider"
import { buildFeedItemContentReportRequest } from "@/lib/feedContentReport"
import { feedContentOwnerUserId } from "@/app/components/feed/feedPostHelpers"

type FeedPostModerationMenuProps = {
  post: unknown
  viewerUserId?: string | null
}

export default function FeedPostModerationMenu({
  post,
  viewerUserId,
}: FeedPostModerationMenuProps) {
  const moderation = useOptionalContentModeration()
  const reportRequest = useMemo(
    () => buildFeedItemContentReportRequest(post, viewerUserId),
    [post, viewerUserId]
  )
  const ownerId = useMemo(() => feedContentOwnerUserId(post), [post])

  const onReport = useCallback(() => {
    if (!reportRequest || !moderation) return
    moderation.openReport(reportRequest)
  }, [moderation, reportRequest])

  const onBlockUser = useCallback(() => {
    if (!ownerId || !moderation) return
    void moderation.confirmBlockUser(
      ownerId,
      reportRequest?.subjectTitle ?? null
    )
  }, [moderation, ownerId, reportRequest?.subjectTitle])

  if (!moderation || !reportRequest) return null

  return (
    <ContentOverflowMenu onReport={onReport} onBlockUser={onBlockUser} />
  )
}
