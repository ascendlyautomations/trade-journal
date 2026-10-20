"use client"

import { useCallback, useMemo } from "react"
import ContentOverflowMenu from "@/app/components/moderation/ContentOverflowMenu"
import { useOptionalContentModeration } from "@/app/components/moderation/ContentModerationProvider"
import { buildUserContentReportRequest } from "@/lib/feedContentReport"

type ProfileVisitorModerationMenuProps = {
  profileId: string
  displayName?: string | null
  viewerUserId?: string | null
}

export default function ProfileVisitorModerationMenu({
  profileId,
  displayName,
  viewerUserId,
}: ProfileVisitorModerationMenuProps) {
  const moderation = useOptionalContentModeration()
  const reportRequest = useMemo(
    () =>
      buildUserContentReportRequest({
        userId: profileId,
        displayName,
        viewerUserId,
      }),
    [displayName, profileId, viewerUserId]
  )

  const onReport = useCallback(() => {
    if (!reportRequest || !moderation) return
    moderation.openReport(reportRequest)
  }, [moderation, reportRequest])

  const onBlockUser = useCallback(() => {
    if (!moderation) return
    void moderation.confirmBlockUser(profileId, displayName)
  }, [displayName, moderation, profileId])

  if (!moderation || !reportRequest) return null

  return (
    <ContentOverflowMenu onReport={onReport} onBlockUser={onBlockUser} />
  )
}
