"use client"

import Link from "next/link"
import { useCallback, useEffect, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import { formatEST } from "@/lib/formatEST"
import { profilePath } from "@/lib/profileRoutes"
import {
  approveIncomingFollowRequest,
  declineIncomingFollowRequest,
} from "@/lib/respondFollowRequest"

export type IncomingFollowRequest = {
  id: string
  requester_id: string
  created_at: string
  requester?: {
    id: string
    username: string | null
    name: string | null
    avatar_url: string | null
  } | null
}

function requesterLabel(request: IncomingFollowRequest): string {
  const p = request.requester
  if (p?.username?.trim()) return p.username.trim()
  if (p?.name?.trim()) return p.name.trim()
  return "User"
}

type FollowRequestsPanelProps = {
  userId: string
  /** Must be true for loadRequests to run. Parent should not mount when false. */
  isPrivate?: boolean
  onResolved?: () => void
}

function logFollowRequestsError(
  action: string,
  meta: Record<string, unknown>,
  error: { code?: string; message?: string; details?: string; hint?: string } | null
) {
  console.error(`[follow-requests] ${action}`, {
    ...meta,
    error: error
      ? {
          code: error.code,
          message: error.message,
          details: error.details,
          hint: error.hint,
        }
      : null,
  })
}

export default function FollowRequestsPanel({
  userId,
  isPrivate = false,
  onResolved,
}: FollowRequestsPanelProps) {
  const [requests, setRequests] = useState<IncomingFollowRequest[]>([])
  const [loading, setLoading] = useState(true)
  const [busyId, setBusyId] = useState<string | null>(null)

  useEffect(() => {
    console.info("[follow-requests] FollowRequestsPanel mounted", {
      userId,
      isPrivate,
    })
    return () => {
      console.info("[follow-requests] FollowRequestsPanel unmounted", {
        userId,
        isPrivate,
      })
    }
  }, [userId, isPrivate])

  const loadRequests = useCallback(async () => {
    if (!userId) {
      console.info("[follow-requests] load skipped", {
        userId,
        isPrivate,
        reason: "no_user_id",
      })
      setRequests([])
      setLoading(false)
      return
    }

    if (isPrivate !== true) {
      console.info("[follow-requests] load skipped", {
        userId,
        isPrivate,
        reason: "not_private_account",
      })
      setRequests([])
      setLoading(false)
      return
    }

    console.info("[follow-requests] load starting", { userId, isPrivate })
    setLoading(true)

    const { data, error } = await supabase
      .from("follow_requests")
      .select("id, requester_id, created_at")
      .eq("target_id", userId)
      .eq("status", "pending")
      .order("created_at", { ascending: false })

    if (error) {
      logFollowRequestsError("load failed", { userId, isPrivate }, error)
      setRequests([])
      setLoading(false)
      return
    }

    const rows = data ?? []
    if (rows.length === 0) {
      setRequests([])
      setLoading(false)
      return
    }

    const requesterIds = rows.map((row) => row.requester_id)
    const { data: profiles } = await supabase
      .from("profiles")
      .select("id, username, name, avatar_url")
      .in("id", requesterIds)

    const profileById = new Map((profiles ?? []).map((p) => [p.id, p]))

    setRequests(
      rows.map((row) => ({
        ...row,
        requester: profileById.get(row.requester_id) ?? null,
      }))
    )
    console.info("[follow-requests] load succeeded", {
      userId,
      isPrivate,
      pendingCount: rows.length,
    })
    setLoading(false)
  }, [userId, isPrivate])

  useEffect(() => {
    void loadRequests()
  }, [loadRequests])

  async function handleApprove(requestId: string) {
    if (busyId) return
    setBusyId(requestId)

    const result = await approveIncomingFollowRequest(supabase, requestId)
    if (!result.ok) {
      setBusyId(null)
      return
    }

    setRequests((prev) => prev.filter((row) => row.id !== requestId))
    setBusyId(null)
    onResolved?.()
  }

  async function handleDecline(requestId: string) {
    if (busyId) return
    setBusyId(requestId)

    const result = await declineIncomingFollowRequest(supabase, requestId)
    if (!result.ok) {
      setBusyId(null)
      return
    }

    setRequests((prev) => prev.filter((row) => row.id !== requestId))
    setBusyId(null)
    onResolved?.()
  }

  if (loading) {
    return (
      <section className="rounded-xl border border-white/10 bg-white/5 p-4">
        <h2 className="text-sm font-semibold text-white">Follow requests</h2>
        <p className="mt-2 text-sm text-gray-400">Loading…</p>
      </section>
    )
  }

  if (requests.length === 0) return null

  return (
    <section className="rounded-xl border border-blue-400/30 bg-blue-500/10 p-4">
      <h2 className="text-sm font-semibold text-white">Follow requests</h2>
      <p className="mt-1 text-xs text-gray-400">
        Approve followers for your private account.
      </p>

      <ul className="mt-3 space-y-2">
        {requests.map((request) => {
          const label = requesterLabel(request)
          const href = profilePath({
            id: request.requester_id,
            username: request.requester?.username,
          })
          const busy = busyId === request.id

          return (
            <li
              key={request.id}
              className="flex flex-col gap-3 rounded-lg border border-white/10 bg-[#0f172a]/60 p-3 sm:flex-row sm:items-center"
            >
              <Link
                href={href}
                className="flex min-w-0 flex-1 items-center gap-3"
              >
                <img
                  src={request.requester?.avatar_url || "/default-avatar.png"}
                  alt=""
                  className="h-10 w-10 shrink-0 rounded-full object-cover ring-2 ring-white/10"
                  onError={(e) => {
                    e.currentTarget.src = "/default-avatar.png"
                  }}
                />
                <div className="min-w-0">
                  <p className="truncate text-sm font-medium text-white">
                    {label}
                  </p>
                  <p className="text-xs text-gray-400">
                    Requested {formatEST(request.created_at)}
                  </p>
                </div>
              </Link>

              <div className="flex shrink-0 gap-2">
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void handleApprove(request.id)}
                  className="rounded-md bg-blue-500 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-blue-600 disabled:opacity-50"
                >
                  Approve
                </button>
                <button
                  type="button"
                  disabled={busy}
                  onClick={() => void handleDecline(request.id)}
                  className="rounded-md border border-white/15 bg-white/5 px-3 py-1.5 text-sm font-medium text-gray-200 transition hover:bg-white/10 disabled:opacity-50"
                >
                  Decline
                </button>
              </div>
            </li>
          )
        })}
      </ul>
    </section>
  )
}
