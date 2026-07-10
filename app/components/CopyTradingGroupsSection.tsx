"use client"

import { useCallback, useEffect, useState } from "react"
import ProGate from "@/app/components/ProGate"
import CopyTradingGroupEditorModal from "@/app/components/CopyTradingGroupEditorModal"
import { ConfirmModal, FeedbackModal, useFeedbackPopup } from "@/app/components/ui"
import EmptyState from "@/app/components/ui/EmptyState"
import { LOADING_COPY } from "@/lib/loadingCopy"
import { handleSupabaseError } from "@/lib/handleSupabaseError"
import { supabase } from "@/lib/supabaseClient"
import {
  COPY_TRADING_GROUPS_DESCRIPTION,
  COPY_TRADING_GROUPS_SETTINGS_DESCRIPTION,
  createCopyTradingGroup,
  deleteCopyTradingGroup,
  fetchCopyTradingGroups,
  resolveCopyGroupAccounts,
  updateCopyTradingGroup,
  type CopyTradingGroup,
} from "@/lib/copyTradingGroups"
import {
  ensureAccountsLoaded,
  getCachedAccounts,
} from "@/lib/appDataCache"
import {
  mapTradingAccountRow,
  tradingAccountDisplayTitle,
  type TradingAccountListItem,
} from "@/lib/tradingAccounts"

type CopyTradingGroupsSectionProps = {
  userId: string | undefined
  isPro: boolean
  /** Settings uses a longer description; /app uses the short marketing copy. */
  variant?: "settings" | "app"
}

function mapCachedAccounts(userId: string): TradingAccountListItem[] {
  return (getCachedAccounts(userId) ?? []).map((row) =>
    mapTradingAccountRow(row as Record<string, unknown>)
  )
}

export default function CopyTradingGroupsSection({
  userId,
  isPro,
  variant = "settings",
}: CopyTradingGroupsSectionProps) {
  const [groups, setGroups] = useState<CopyTradingGroup[]>([])
  const [accounts, setAccounts] = useState<TradingAccountListItem[]>([])
  const [loading, setLoading] = useState(Boolean(userId))
  const [editorOpen, setEditorOpen] = useState(false)
  const [editingGroup, setEditingGroup] = useState<CopyTradingGroup | null>(null)
  const [saving, setSaving] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<CopyTradingGroup | null>(null)
  const [deleting, setDeleting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const { showPopup, feedbackModalProps } = useFeedbackPopup({ autoDismissMs: 2500 })

  const description =
    variant === "settings"
      ? COPY_TRADING_GROUPS_SETTINGS_DESCRIPTION
      : COPY_TRADING_GROUPS_DESCRIPTION

  const refresh = useCallback(async () => {
    if (!userId) {
      setGroups([])
      setAccounts([])
      setLoading(false)
      return
    }

    setLoading(true)
    setError(null)

    try {
      const accountRows = await ensureAccountsLoaded(supabase, userId)
      setAccounts(
        accountRows.map((row) => mapTradingAccountRow(row as Record<string, unknown>))
      )

      if (!isPro) {
        setGroups([])
        setLoading(false)
        return
      }

      const { groups: nextGroups, error: groupsError } = await fetchCopyTradingGroups(
        supabase,
        userId
      )
      if (groupsError) {
        setError(groupsError.message)
        setGroups([])
      } else {
        setGroups(nextGroups)
      }
    } catch (err) {
      setError(handleSupabaseError(err))
      setGroups([])
    } finally {
      setLoading(false)
    }
  }, [userId, isPro])

  useEffect(() => {
    if (!userId) {
      setAccounts([])
      setGroups([])
      setLoading(false)
      return
    }
    setAccounts(mapCachedAccounts(userId))
    void refresh()
  }, [userId, refresh])

  function openCreate() {
    setEditingGroup(null)
    setEditorOpen(true)
  }

  function openEdit(group: CopyTradingGroup) {
    setEditingGroup(group)
    setEditorOpen(true)
  }

  async function handleSave(payload: { name: string; accountIds: string[] }) {
    if (!userId || saving) return
    const wasEditing = Boolean(editingGroup)
    setSaving(true)
    setError(null)

    const result = editingGroup
      ? await updateCopyTradingGroup(
          supabase,
          userId,
          editingGroup.id,
          payload.name,
          payload.accountIds
        )
      : await createCopyTradingGroup(
          supabase,
          userId,
          payload.name,
          payload.accountIds
        )

    setSaving(false)

    if (result.error) {
      setError(result.error.message)
      return
    }

    setEditorOpen(false)
    setEditingGroup(null)
    await refresh()
    showPopup({
      type: "success",
      message: wasEditing
        ? "Copy trading group updated"
        : "Copy trading group saved",
    })
  }

  async function confirmDelete() {
    if (!userId || !deleteTarget || deleting) return
    setDeleting(true)
    const { error: deleteError } = await deleteCopyTradingGroup(
      supabase,
      userId,
      deleteTarget.id
    )
    setDeleting(false)

    if (deleteError) {
      setError(deleteError.message)
      return
    }

    setDeleteTarget(null)
    await refresh()
  }

  return (
    <>
      <section
        id="copy-trading-groups"
        className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm"
      >
        <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h3 className="text-sm font-semibold uppercase tracking-wide text-blue-300">
              Copy Trading Groups
            </h3>
            <p className="mt-1 max-w-2xl text-sm text-gray-400">{description}</p>
          </div>
          {isPro ? (
            <button
              type="button"
              onClick={openCreate}
              className="shrink-0 rounded-lg bg-blue-500 px-4 py-2 text-sm font-medium text-white transition hover:bg-blue-600"
            >
              + Create Copy Trading Group
            </button>
          ) : null}
        </div>

        {!isPro ? (
          <div className="mt-4">
            <ProGate isPro={false} />
          </div>
        ) : loading ? (
          <p className="mt-4 text-sm text-gray-500">{LOADING_COPY.copyTradingGroups}</p>
        ) : error ? (
          <p className="mt-4 text-sm text-red-300">{error}</p>
        ) : groups.length === 0 ? (
          <EmptyState
            icon="📑"
            title="No copy trading groups yet"
            description="Create a group to journal the same trade across multiple accounts at once."
            action={
              <button
                type="button"
                onClick={openCreate}
                className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-blue-600"
              >
                + Create Copy Trading Group
              </button>
            }
            className="mt-4"
          />
        ) : (
          <div className="mt-4 space-y-3">
            {groups.map((group) => {
              const linkedAccounts = resolveCopyGroupAccounts(group, accounts)
              return (
                <article
                  key={group.id}
                  className="rounded-xl border border-white/10 bg-black/20 p-4"
                >
                  <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                    <div className="min-w-0">
                      <h4 className="text-base font-semibold text-white">{group.name}</h4>
                      <p className="mt-1 text-xs text-gray-500">
                        {linkedAccounts.length} linked account
                        {linkedAccounts.length === 1 ? "" : "s"}
                      </p>
                      {linkedAccounts.length > 0 ? (
                        <ul className="mt-2 space-y-1 text-sm text-gray-300">
                          {linkedAccounts.map((account) => (
                            <li key={account.id} className="truncate">
                              {tradingAccountDisplayTitle(account)}
                            </li>
                          ))}
                        </ul>
                      ) : (
                        <p className="mt-2 text-sm text-amber-200/90">
                          No linked accounts — edit this group to add accounts.
                        </p>
                      )}
                    </div>
                    <div className="flex shrink-0 flex-wrap gap-2">
                      <button
                        type="button"
                        onClick={() => openEdit(group)}
                        className="rounded-md border border-white/20 px-3 py-1.5 text-xs font-medium text-white transition hover:bg-white/10"
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        onClick={() => setDeleteTarget(group)}
                        className="rounded-md border border-red-400/40 px-3 py-1.5 text-xs font-medium text-red-300 transition hover:bg-red-500/10"
                      >
                        Delete
                      </button>
                    </div>
                  </div>
                </article>
              )
            })}
          </div>
        )}
      </section>

      <CopyTradingGroupEditorModal
        open={editorOpen}
        accounts={accounts}
        editingGroup={editingGroup}
        saving={saving}
        onClose={() => {
          if (saving) return
          setEditorOpen(false)
          setEditingGroup(null)
        }}
        onSave={(payload) => void handleSave(payload)}
      />

      <ConfirmModal
        open={deleteTarget != null}
        title="Delete copy trading group?"
        description={
          deleteTarget
            ? `"${deleteTarget.name}" will be removed. Existing trades keep their journal entries.`
            : ""
        }
        confirmLabel="Delete"
        loading={deleting}
        loadingLabel="Deleting…"
        destructive
        onCancel={() => {
          if (deleting) return
          setDeleteTarget(null)
        }}
        onConfirm={() => void confirmDelete()}
      />

      <FeedbackModal {...feedbackModalProps} />
    </>
  )
}
