"use client"

import Link from "next/link"
import { useCallback, useEffect, useState } from "react"
import { ProfileAvatarImg } from "@/app/components/SafeProfileAvatar"
import {
  contentReportReasonLabel,
  contentReportStatusLabel,
  contentReportTargetLabel,
} from "@/lib/contentReports"
import {
  DM_PRIVACY_OPTIONS,
  fetchOwnerDmPrivacy,
  persistOwnerDmPrivacy,
  type DmPrivacy,
} from "@/lib/dmPrivacy"
import {
  fetchBlockedAccountsList,
  fetchMutedDmPeersList,
  fetchMyContentReports,
  persistProfileIsPrivate,
  unmuteDmPeerConversation,
  type BlockedAccountListRow,
  type MutedDmPeerListRow,
} from "@/lib/settingsPrivacy"
import { setUserBlocked } from "@/lib/userBlocks"
import {
  noteUnblockedPeer,
  subscribeBlockedPeerList,
  USER_BLOCK_LIST_CHANGED_EVENT,
} from "@/lib/blockedPeersClient"
import { profilePath } from "@/lib/profileRoutes"
import type { ContentReportRow } from "@/lib/contentReports"

function SettingsPrivateProfileControl({
  isPrivate,
  onToggle,
  busy,
}: {
  isPrivate: boolean
  onToggle: () => void
  busy?: boolean
}) {
  return (
    <div className="flex flex-col gap-3 rounded-xl border border-white/10 bg-black/20 p-4 sm:flex-row sm:items-center sm:justify-between">
      <div>
        <p className="font-medium text-white">Private profile</p>
        <p className="text-xs text-gray-400">
          Only approved followers can see your full profile. Others must request
          to follow you.
        </p>
      </div>
      <button
        type="button"
        onClick={onToggle}
        disabled={busy}
        aria-pressed={isPrivate}
        className={`shrink-0 rounded-lg px-4 py-2 text-sm font-medium transition disabled:opacity-50 ${
          isPrivate ? "bg-blue-500 text-white" : "bg-white/10 text-white"
        }`}
      >
        {busy ? "Saving…" : isPrivate ? "On" : "Off"}
      </button>
    </div>
  )
}

function formatReportDate(iso: string): string {
  const ms = Date.parse(iso)
  if (!Number.isFinite(ms)) return iso
  return new Date(ms).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  })
}

type SettingsPrivacySectionProps = {
  userId: string
  isPrivate: boolean
  onIsPrivateChange: (next: boolean) => void
  onProfilePatch: (patch: { is_private: boolean }) => void
  showError: (message: string) => void
}

export default function SettingsPrivacySection({
  userId,
  isPrivate,
  onIsPrivateChange,
  onProfilePatch,
  showError,
}: SettingsPrivacySectionProps) {
  const [privateBusy, setPrivateBusy] = useState(false)
  const [dmPrivacy, setDmPrivacy] = useState<DmPrivacy>("everyone")
  const [dmPrivacyBusy, setDmPrivacyBusy] = useState(false)
  const [blocked, setBlocked] = useState<BlockedAccountListRow[]>([])
  const [muted, setMuted] = useState<MutedDmPeerListRow[]>([])
  const [reports, setReports] = useState<ContentReportRow[]>([])
  const [listsLoading, setListsLoading] = useState(true)
  const [listsError, setListsError] = useState<string | null>(null)
  const [unblockBusyId, setUnblockBusyId] = useState<string | null>(null)
  const [unmuteBusyId, setUnmuteBusyId] = useState<string | null>(null)

  const refreshLists = useCallback(async () => {
    setListsLoading(true)
    setListsError(null)
    const [blockedResult, mutedResult, reportsResult, dmResult] =
      await Promise.all([
      fetchBlockedAccountsList(),
      fetchMutedDmPeersList(),
      fetchMyContentReports(userId),
      fetchOwnerDmPrivacy(userId),
    ])
    if (!blockedResult.ok) {
      setListsError(blockedResult.message)
    } else {
      setBlocked(blockedResult.rows)
    }
    if (!mutedResult.ok) {
      setListsError((prev) => prev ?? mutedResult.message)
    } else {
      setMuted(mutedResult.rows)
    }
    if (dmResult.ok) {
      setDmPrivacy(dmResult.value)
    } else {
      setListsError((prev) => prev ?? dmResult.message)
    }
    if (!reportsResult.ok) {
      setListsError((prev) => prev ?? reportsResult.message)
    } else {
      setReports(reportsResult.rows)
    }
    setListsLoading(false)
  }, [userId])

  useEffect(() => {
    void refreshLists()
  }, [refreshLists])

  useEffect(() => {
    return subscribeBlockedPeerList(() => {
      void refreshLists()
    })
  }, [refreshLists])

  async function handleTogglePrivate() {
    const next = !isPrivate
    setPrivateBusy(true)
    onIsPrivateChange(next)
    const result = await persistProfileIsPrivate(userId, next)
    setPrivateBusy(false)
    if (!result.ok) {
      onIsPrivateChange(isPrivate)
      showError(result.message)
      return
    }
    onProfilePatch({ is_private: next })
  }

  async function handleDmPrivacyChange(next: DmPrivacy) {
    if (next === dmPrivacy) return
    const previous = dmPrivacy
    setDmPrivacy(next)
    setDmPrivacyBusy(true)
    const result = await persistOwnerDmPrivacy(userId, next)
    setDmPrivacyBusy(false)
    if (!result.ok) {
      setDmPrivacy(previous)
      showError(result.message)
      return
    }
    setDmPrivacy(result.value)
  }

  async function handleUnmute(row: MutedDmPeerListRow) {
    setUnmuteBusyId(row.peer_id)
    const result = await unmuteDmPeerConversation(userId, row.conversation_id)
    setUnmuteBusyId(null)
    if (!result.ok) {
      showError(result.message)
      return
    }
    setMuted((prev) => prev.filter((item) => item.peer_id !== row.peer_id))
  }

  async function handleUnblock(blockedId: string) {
    setUnblockBusyId(blockedId)
    const result = await setUserBlocked(blockedId, false)
    setUnblockBusyId(null)
    if (!result.ok) {
      showError(result.message)
      return
    }
    noteUnblockedPeer(blockedId)
    setBlocked((prev) => prev.filter((row) => row.blocked_id !== blockedId))
    if (typeof window !== "undefined") {
      window.dispatchEvent(new CustomEvent(USER_BLOCK_LIST_CHANGED_EVENT))
    }
  }

  return (
    <div
      className="space-y-8 rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm"
      data-testid="settings.privacy"
    >
      <section className="space-y-3">
        <h3 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
          Profile visibility
        </h3>
        <SettingsPrivateProfileControl
          isPrivate={isPrivate}
          onToggle={() => void handleTogglePrivate()}
          busy={privateBusy}
        />
      </section>

      <section className="space-y-3">
        <h3 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
          Who can message me
        </h3>
        <p className="text-xs text-gray-500">
          This applies to new direct messages. Existing conversations are not
          affected.
        </p>
        <ul className="divide-y divide-white/10 overflow-hidden rounded-xl border border-white/10 bg-black/20">
          {DM_PRIVACY_OPTIONS.map((option) => {
            const selected = dmPrivacy === option.value
            return (
              <li key={option.value}>
                <button
                  type="button"
                  disabled={dmPrivacyBusy}
                  onClick={() => void handleDmPrivacyChange(option.value)}
                  className="flex w-full items-start gap-3 px-4 py-3 text-left transition hover:bg-white/5 disabled:opacity-50"
                  data-testid={`settings.privacy.dm.${option.value}`}
                >
                  <div className="min-w-0 flex-1">
                    <p className="text-sm font-medium text-white">
                      {option.title}
                    </p>
                    <p className="mt-0.5 text-xs text-gray-400">
                      {option.subtitle}
                    </p>
                  </div>
                  {selected ? (
                    <span className="shrink-0 text-sm font-semibold text-blue-400">
                      ✓
                    </span>
                  ) : null}
                </button>
              </li>
            )
          })}
        </ul>
      </section>

      <section className="space-y-3">
        <div className="flex items-baseline justify-between gap-2">
          <h3 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
            Blocked accounts
          </h3>
          <span className="text-xs text-gray-500">
            {listsLoading ? "…" : blocked.length === 0 ? "None" : blocked.length}
          </span>
        </div>
        <p className="text-xs text-gray-500">
          Blocked users cannot message you and their content is hidden where
          applicable.
        </p>
        {listsError ? (
          <p className="text-sm text-red-400">
            {listsError}{" "}
            <button
              type="button"
              className="underline"
              onClick={() => void refreshLists()}
            >
              Retry
            </button>
          </p>
        ) : null}
        {listsLoading && blocked.length === 0 ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : blocked.length === 0 ? (
          <p className="rounded-xl border border-white/10 bg-black/20 px-4 py-3 text-sm text-gray-400">
            You haven&apos;t blocked anyone.
          </p>
        ) : (
          <ul className="divide-y divide-white/10 overflow-hidden rounded-xl border border-white/10 bg-black/20">
            {blocked.map((row) => {
              const label =
                row.username?.trim() ||
                row.name?.trim() ||
                "Blocked user"
              return (
                <li
                  key={row.blocked_id}
                  className="flex items-center gap-3 px-4 py-3"
                >
                  <Link
                    href={profilePath({
                      id: row.blocked_id,
                      username: row.username ?? undefined,
                    })}
                    className="flex min-w-0 flex-1 items-center gap-3"
                  >
                    <ProfileAvatarImg
                      src={row.avatar_url}
                      className="h-10 w-10 shrink-0"
                    />
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-white">
                        {label}
                      </p>
                      {row.name && row.username ? (
                        <p className="truncate text-xs text-gray-400">
                          @{row.username.replace(/^@/, "")}
                        </p>
                      ) : null}
                    </div>
                  </Link>
                  <button
                    type="button"
                    disabled={unblockBusyId === row.blocked_id}
                    onClick={() => void handleUnblock(row.blocked_id)}
                    className="shrink-0 text-sm font-semibold text-blue-400 hover:text-blue-300 disabled:opacity-50"
                  >
                    Unblock
                  </button>
                </li>
              )
            })}
          </ul>
        )}
      </section>

      <section className="space-y-3">
        <div className="flex items-baseline justify-between gap-2">
          <h3 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
            Muted accounts
          </h3>
          <span className="text-xs text-gray-500">
            {listsLoading ? "…" : muted.length === 0 ? "None" : muted.length}
          </span>
        </div>
        <p className="text-xs text-gray-500">
          Muting turns off notifications for a direct message conversation. You
          can still read messages when you open the chat. This is separate from
          muting notifications inside a community room.
        </p>
        {listsLoading && muted.length === 0 ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : muted.length === 0 ? (
          <p className="rounded-xl border border-white/10 bg-black/20 px-4 py-3 text-sm text-gray-400">
            Muted conversations will appear here.
          </p>
        ) : (
          <ul
            className="divide-y divide-white/10 overflow-hidden rounded-xl border border-white/10 bg-black/20"
            data-testid="settings.privacy.muted"
          >
            {muted.map((row) => {
              const label =
                row.username?.trim() ||
                row.name?.trim() ||
                "Muted account"
              return (
                <li
                  key={row.peer_id}
                  className="flex items-center gap-3 px-4 py-3"
                >
                  <Link
                    href={profilePath({
                      id: row.peer_id,
                      username: row.username ?? undefined,
                    })}
                    className="flex min-w-0 flex-1 items-center gap-3"
                  >
                    <ProfileAvatarImg
                      src={row.avatar_url}
                      className="h-10 w-10 shrink-0"
                    />
                    <div className="min-w-0">
                      <p className="truncate text-sm font-medium text-white">
                        {label}
                      </p>
                      {row.name && row.username ? (
                        <p className="truncate text-xs text-gray-400">
                          @{row.username.replace(/^@/, "")}
                        </p>
                      ) : null}
                    </div>
                  </Link>
                  <button
                    type="button"
                    disabled={unmuteBusyId === row.peer_id}
                    onClick={() => void handleUnmute(row)}
                    className="shrink-0 text-sm font-semibold text-blue-400 hover:text-blue-300 disabled:opacity-50"
                  >
                    Unmute
                  </button>
                </li>
              )
            })}
          </ul>
        )}
      </section>

      <section className="space-y-3">
        <div className="flex items-baseline justify-between gap-2">
          <h3 className="text-sm font-semibold uppercase tracking-wide text-gray-400">
            Your reports
          </h3>
          <span className="text-xs text-gray-500">
            {listsLoading ? "…" : reports.length === 0 ? "None" : reports.length}
          </span>
        </div>
        <p className="text-xs text-gray-500">
          Content you reported for review under the Community Guidelines.
        </p>
        {listsLoading && reports.length === 0 ? (
          <p className="text-sm text-gray-400">Loading…</p>
        ) : reports.length === 0 ? (
          <p className="rounded-xl border border-white/10 bg-black/20 px-4 py-3 text-sm text-gray-400">
            You haven&apos;t submitted any reports yet.
          </p>
        ) : (
          <ul className="divide-y divide-white/10 overflow-hidden rounded-xl border border-white/10 bg-black/20">
            {reports.map((row) => (
              <li key={row.id} className="px-4 py-3">
                <p className="text-sm font-medium text-white">
                  {contentReportTargetLabel(row.target_type)}
                  <span className="font-normal text-gray-400">
                    {" · "}
                    {contentReportReasonLabel(row.reason)}
                  </span>
                </p>
                <p className="mt-0.5 text-xs text-gray-500">
                  {formatReportDate(row.created_at)}
                  {" · "}
                  {contentReportStatusLabel(row.status)}
                </p>
              </li>
            ))}
          </ul>
        )}
      </section>
    </div>
  )
}
