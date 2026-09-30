"use client"

import Link from "next/link"
import { useCallback, useEffect, useMemo, useState } from "react"
import { getCurrentAdminCheckResult } from "@/lib/adminUsers"
import {
  PLATFORM_UPDATE_CATEGORIES,
  PLATFORM_UPDATE_CATEGORY_LABELS,
  PLATFORM_UPDATE_DESTINATIONS,
  PLATFORM_UPDATE_DESTINATION_LABELS,
  type PlatformUpdateCategoryId,
  type PlatformUpdateDestinationId,
} from "@/lib/platformUpdateDestinations"
import {
  createAdminPlatformUpdate,
  deleteAdminPlatformUpdate,
  fetchAdminPlatformUpdates,
  patchAdminPlatformUpdate,
  publishAdminPlatformUpdate,
  type AdminPlatformUpdate,
} from "@/lib/platformUpdatesClient"

const emptyForm = {
  title: "",
  body: "",
  category: "announcement" as PlatformUpdateCategoryId,
  destination: "whats_new" as PlatformUpdateDestinationId,
  sendPush: false,
}

export default function AdminUpdatesPage() {
  const [allowed, setAllowed] = useState(false)
  const [checking, setChecking] = useState(true)
  const [updates, setUpdates] = useState<AdminPlatformUpdate[]>([])
  const [error, setError] = useState<string | null>(null)
  const [form, setForm] = useState(emptyForm)
  const [editingId, setEditingId] = useState<string | null>(null)
  const [confirmPublish, setConfirmPublish] = useState(false)
  const [busy, setBusy] = useState(false)
  const [publishNotice, setPublishNotice] = useState<string | null>(null)
  const [deleteTargetId, setDeleteTargetId] = useState<string | null>(null)
  const [deleteTargetPublished, setDeleteTargetPublished] = useState(false)

  const load = useCallback(async () => {
    const rows = await fetchAdminPlatformUpdates()
    setUpdates(rows)
  }, [])

  useEffect(() => {
    ;(async () => {
      const check = await getCurrentAdminCheckResult()
      setAllowed(check.isAdmin)
      setChecking(false)
      if (check.isAdmin) {
        try {
          await load()
        } catch (e) {
          setError(e instanceof Error ? e.message : "Failed to load")
        }
      }
    })()
  }, [load])

  const grouped = useMemo(
    () => ({
      drafts: updates.filter((u) => u.status === "draft"),
      published: updates.filter((u) => u.status === "published"),
    }),
    [updates]
  )

  function startCreate() {
    setEditingId(null)
    setForm(emptyForm)
  }

  function startEdit(row: AdminPlatformUpdate) {
    if (row.status !== "draft") return
    setEditingId(row.id)
    setForm({
      title: row.title,
      body: row.body,
      category: row.category,
      destination: row.destination,
      sendPush: row.sendPush,
    })
  }

  async function persistDraftId(): Promise<string> {
    if (editingId) {
      await patchAdminPlatformUpdate(editingId, {
        title: form.title,
        body: form.body,
        category: form.category,
        destination: form.destination,
        sendPush: form.sendPush,
      })
      return editingId
    }
    const created = await createAdminPlatformUpdate({
      title: form.title,
      body: form.body,
      category: form.category,
      destination: form.destination,
      sendPush: form.sendPush,
    })
    setEditingId(created.id)
    return created.id
  }

  async function saveDraft() {
    setBusy(true)
    setError(null)
    try {
      await persistDraftId()
      await load()
    } catch (e) {
      setError(e instanceof Error ? e.message : "Save failed")
    } finally {
      setBusy(false)
    }
  }

  async function runPublish() {
    setBusy(true)
    setError(null)
    setPublishNotice(null)
    try {
      const id = await persistDraftId()
      const result = await publishAdminPlatformUpdate(id)
      setConfirmPublish(false)
      await load()
      startCreate()
      if (result.pushDelivery) {
        const d = result.pushDelivery
        if (d.successCount > 0) {
          setPublishNotice(
            `Published. Push delivered to ${d.successCount} device(s)` +
              (d.failedCount > 0 ? ` (${d.failedCount} failed).` : ".")
          )
        } else {
          setError(
            `Published to What's New, but push did not deliver. ` +
              `Broadcast ${d.status}; tokens in DB: ${d.iosTokenRows}; ` +
              `attempted ${d.attemptedCount}; ` +
              (d.lastApnsFailureReason
                ? `reason: ${d.lastApnsFailureReason}`
                : "check Vercel logs for [platform-update-broadcast].")
          )
        }
        if (d.incomplete) {
          setPublishNotice(
            (prev) =>
              `${prev ?? ""} Broadcast still sending (large audience).`.trim()
          )
        }
      } else {
        setPublishNotice("Published (no push requested).")
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : "Publish failed")
    } finally {
      setBusy(false)
    }
  }

  if (checking) {
    return <p className="p-8 text-gray-300">Checking access…</p>
  }
  if (!allowed) {
    return <p className="p-8 text-red-300">Admin access required.</p>
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] p-4 md:p-8 text-gray-100">
      <div className="mx-auto max-w-5xl space-y-8">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <Link href="/admin" className="text-sm text-blue-300 hover:underline">
              ← Admin
            </Link>
            <h1 className="mt-2 text-2xl font-bold text-blue-200">Updates</h1>
            <p className="text-sm text-gray-400">
              Publish What&apos;s New entries and optional broadcast pushes.
            </p>
          </div>
          <Link
            href="/whats-new"
            className="text-sm text-emerald-300 hover:underline"
          >
            View user page
          </Link>
        </div>

        {error && (
          <p className="rounded-lg border border-red-500/40 bg-red-500/10 px-3 py-2 text-sm text-red-200">
            {error}
          </p>
        )}
        {publishNotice && (
          <p className="rounded-lg border border-emerald-500/40 bg-emerald-500/10 px-3 py-2 text-sm text-emerald-100">
            {publishNotice}
          </p>
        )}

        <section className="rounded-xl border border-white/10 bg-black/20 p-4 space-y-4">
          <h2 className="text-lg font-semibold">
            {editingId ? "Edit draft" : "New update"}
          </h2>
          <div className="grid gap-3 md:grid-cols-2">
            <label className="block text-sm">
              Title
              <input
                className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2"
                value={form.title}
                onChange={(e) => setForm({ ...form, title: e.target.value })}
              />
            </label>
            <label className="block text-sm">
              Category
              <select
                className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2"
                value={form.category}
                onChange={(e) =>
                  setForm({
                    ...form,
                    category: e.target.value as PlatformUpdateCategoryId,
                  })
                }
              >
                {PLATFORM_UPDATE_CATEGORIES.map((c) => (
                  <option key={c} value={c}>
                    {PLATFORM_UPDATE_CATEGORY_LABELS[c]}
                  </option>
                ))}
              </select>
            </label>
          </div>
          <label className="block text-sm">
            Body
            <textarea
              className="mt-1 min-h-[120px] w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2"
              value={form.body}
              onChange={(e) => setForm({ ...form, body: e.target.value })}
            />
          </label>
          <label className="block text-sm">
            Opens To
            <select
              className="mt-1 w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2"
              value={form.destination}
              onChange={(e) =>
                setForm({
                  ...form,
                  destination: e.target.value as PlatformUpdateDestinationId,
                })
              }
            >
              {PLATFORM_UPDATE_DESTINATIONS.map((d) => (
                <option key={d} value={d}>
                  {PLATFORM_UPDATE_DESTINATION_LABELS[d]}
                </option>
              ))}
            </select>
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={form.sendPush}
              onChange={(e) => setForm({ ...form, sendPush: e.target.checked })}
            />
            Send push notification to all registered iOS devices
          </label>
          <div className="flex flex-wrap gap-2">
            <button
              type="button"
              disabled={busy}
              className="rounded-lg bg-white/10 px-4 py-2 text-sm font-medium hover:bg-white/20 disabled:opacity-50"
              onClick={() => void saveDraft()}
            >
              Save draft
            </button>
            <button
              type="button"
              disabled={busy}
              className="rounded-lg bg-emerald-600 px-4 py-2 text-sm font-semibold hover:bg-emerald-500 disabled:opacity-50"
              onClick={() => setConfirmPublish(true)}
            >
              {form.sendPush ? "Publish & Send" : "Publish now"}
            </button>
            <button
              type="button"
              className="rounded-lg px-4 py-2 text-sm text-gray-300 hover:bg-white/5"
              onClick={startCreate}
            >
              Clear
            </button>
          </div>
          {confirmPublish && (
            <div className="rounded-lg border border-amber-500/40 bg-amber-500/10 p-3 text-sm">
              <p>
                {form.sendPush
                  ? "Publish this update and send a push notification to all TradeTraxs users?"
                  : "Publish this update?"}
              </p>
              <div className="mt-3 flex gap-2">
                <button
                  type="button"
                  className="rounded bg-emerald-600 px-3 py-1.5 font-semibold"
                  onClick={() => void runPublish()}
                >
                  {form.sendPush ? "Publish & Send" : "Publish"}
                </button>
                <button
                  type="button"
                  className="rounded bg-white/10 px-3 py-1.5"
                  onClick={() => setConfirmPublish(false)}
                >
                  Cancel
                </button>
              </div>
            </div>
          )}
        </section>

        <UpdateSection
          title="Drafts"
          rows={grouped.drafts}
          onEdit={startEdit}
          onDelete={(id) => {
            void (async () => {
              await deleteAdminPlatformUpdate(id)
              if (editingId === id) startCreate()
              await load()
            })()
          }}
        />
        <UpdateSection
          title="Published"
          rows={grouped.published}
          published
          onDelete={(id) => {
            setDeleteTargetId(id)
            setDeleteTargetPublished(true)
          }}
        />

        {deleteTargetPublished && deleteTargetId && (
          <div
            className="fixed inset-0 z-50 flex items-end justify-center bg-black/50 p-4 sm:items-center"
            role="dialog"
            aria-labelledby="delete-update-title"
          >
            <div className="w-full max-w-md rounded-xl border border-white/10 bg-[#0f172a] p-4 shadow-xl">
              <h3 id="delete-update-title" className="text-lg font-semibold text-white">
                Delete Update?
              </h3>
              <p className="mt-2 text-sm text-gray-300">
                This will permanently remove this announcement from What&apos;s New for all
                users.
              </p>
              <div className="mt-4 flex justify-end gap-2">
                <button
                  type="button"
                  className="rounded-lg px-4 py-2 text-sm text-gray-300 hover:bg-white/5"
                  onClick={() => {
                    setDeleteTargetId(null)
                    setDeleteTargetPublished(false)
                  }}
                >
                  Cancel
                </button>
                <button
                  type="button"
                  className="rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white hover:bg-red-500"
                  onClick={() =>
                    void (async () => {
                      const id = deleteTargetId
                      setDeleteTargetId(null)
                      setDeleteTargetPublished(false)
                      try {
                        await deleteAdminPlatformUpdate(id)
                        if (editingId === id) startCreate()
                        await load()
                      } catch (e) {
                        setError(e instanceof Error ? e.message : "Delete failed")
                      }
                    })()
                  }
                >
                  Delete Update
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function UpdateSection({
  title,
  rows,
  onEdit,
  onDelete,
  published,
}: {
  title: string
  rows: AdminPlatformUpdate[]
  onEdit?: (row: AdminPlatformUpdate) => void
  onDelete?: (id: string) => void | Promise<void>
  published?: boolean
}) {
  if (!rows.length) return null
  return (
    <section className="space-y-3">
      <h2 className="text-lg font-semibold text-blue-200">{title}</h2>
      <ul className="space-y-3">
        {rows.map((row) => (
          <li
            key={row.id}
            className="rounded-xl border border-white/10 bg-black/20 p-4 text-sm"
          >
            <div className="flex flex-wrap items-start justify-between gap-2">
              <div>
                <p className="font-semibold text-white">{row.title}</p>
                <p className="text-xs text-gray-400">
                  {PLATFORM_UPDATE_CATEGORY_LABELS[row.category]} ·{" "}
                  {PLATFORM_UPDATE_DESTINATION_LABELS[row.destination]}
                  {row.sendPush ? " · push" : ""}
                </p>
                {row.publishedAt && (
                  <p className="text-xs text-gray-500">
                    Published {new Date(row.publishedAt).toLocaleString()}
                  </p>
                )}
                {published && row.broadcast && row.sendPush && (
                  <p className="mt-1 text-xs text-gray-400">
                    Broadcast: {row.broadcast.status} · attempted{" "}
                    {row.broadcast.attemptedCount} · success{" "}
                    {row.broadcast.successCount} · failed{" "}
                    {row.broadcast.failedCount}
                  </p>
                )}
              </div>
              <div className="flex gap-2">
                {onEdit && (
                  <button
                    type="button"
                    className="rounded bg-white/10 px-2 py-1 text-xs"
                    onClick={() => onEdit(row)}
                  >
                    Edit
                  </button>
                )}
                {onDelete && (
                  <button
                    type="button"
                    className="rounded bg-red-500/20 px-2 py-1 text-xs text-red-200"
                    aria-label="Delete update"
                    onClick={() => onDelete(row.id)}
                  >
                    Delete
                  </button>
                )}
              </div>
            </div>
            {!published && (
              <p className="mt-2 line-clamp-3 text-gray-300">{row.body}</p>
            )}
          </li>
        ))}
      </ul>
    </section>
  )
}
