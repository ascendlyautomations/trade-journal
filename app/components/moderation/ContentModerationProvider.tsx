"use client"

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react"
import ContentReportModal from "@/app/components/moderation/ContentReportModal"
import type { ContentReportRequest } from "@/lib/feedContentReport"
import { noteBlockedPeer } from "@/lib/blockedPeersClient"
import { setUserBlocked } from "@/lib/userBlocks"
import { useToast } from "@/app/components/ui"

type ContentModerationContextValue = {
  openReport: (request: ContentReportRequest) => void
  blockUser: (userId: string, displayName?: string | null) => Promise<void>
  confirmBlockUser: (userId: string, displayName?: string | null) => Promise<void>
}

const ContentModerationContext =
  createContext<ContentModerationContextValue | null>(null)

export function useContentModeration(): ContentModerationContextValue {
  const ctx = useContext(ContentModerationContext)
  if (!ctx) {
    throw new Error("useContentModeration requires ContentModerationProvider")
  }
  return ctx
}

export function useOptionalContentModeration(): ContentModerationContextValue | null {
  return useContext(ContentModerationContext)
}

export default function ContentModerationProvider({
  children,
}: {
  children: ReactNode
}) {
  const toast = useToast()
  const [reportOpen, setReportOpen] = useState(false)
  const [reportRequest, setReportRequest] =
    useState<ContentReportRequest | null>(null)

  const openReport = useCallback((request: ContentReportRequest) => {
    setReportRequest(request)
    setReportOpen(true)
  }, [])

  const blockUser = useCallback(async (userId: string) => {
    const result = await setUserBlocked(userId, true)
    if (!result.ok) {
      throw new Error(result.message)
    }
    noteBlockedPeer(userId)
  }, [])

  const confirmBlockUser = useCallback(
    async (userId: string, displayName?: string | null) => {
      const label = String(displayName ?? "").trim() || "this user"
      const ok = window.confirm(`Block ${label}? They won't be able to interact with you on TradeTraxs.`)
      if (!ok) return
      await blockUser(userId)
      toast.success("User blocked")
    },
    [blockUser, toast]
  )

  const value = useMemo(
    () => ({ openReport, blockUser, confirmBlockUser }),
    [blockUser, confirmBlockUser, openReport]
  )

  return (
    <ContentModerationContext.Provider value={value}>
      {children}
      <ContentReportModal
        open={reportOpen}
        request={reportRequest}
        onClose={() => {
          setReportOpen(false)
          setReportRequest(null)
        }}
        onBlockUser={blockUser}
      />
    </ContentModerationContext.Provider>
  )
}
