"use client"

import { useCallback, useEffect, useRef, useState } from "react"
import { useRouter } from "next/navigation"
import { supabase } from "@/lib/supabaseClient"
import { useVault } from "@/lib/vault/VaultProvider"
import { vaultListItems } from "@/lib/vault/repository"
import { resolveVaultItemHref } from "@/lib/vault/navigation"
import type { VaultContentFilter, VaultFolder, VaultItem } from "@/lib/vault/types"
import {
  vaultContentFilterLabel,
  vaultContentTypeLabel,
  vaultItemTitle,
} from "@/lib/vault/types"
import { normalizedVaultFolderName } from "@/lib/vault/support"
import VaultHexagonIcon from "./VaultHexagonIcon"
import Modal from "@/app/components/ui/Modal"
import Button from "@/app/components/ui/Button"

const FILTERS: VaultContentFilter[] = [
  "all",
  "trades",
  "clips",
  "posts",
  "achievements",
]

function relativeSavedAt(iso: string): string {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) return ""
  const diffMs = Date.now() - date.getTime()
  const mins = Math.floor(diffMs / 60000)
  if (mins < 1) return "Just now"
  if (mins < 60) return `${mins}m ago`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours}h ago`
  const days = Math.floor(hours / 24)
  if (days < 7) return `${days}d ago`
  return date.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: date.getFullYear() !== new Date().getFullYear() ? "numeric" : undefined,
  })
}

export default function VaultHome() {
  const router = useRouter()
  const vault = useVault()
  const [filter, setFilter] = useState<VaultContentFilter>("all")
  const [selectedFolderId, setSelectedFolderId] = useState<string | null>(null)
  const [items, setItems] = useState<VaultItem[]>([])
  const [folders, setFolders] = useState<VaultFolder[]>([])
  const [nextCursor, setNextCursor] = useState<string | null>(null)
  const [phase, setPhase] = useState<"idle" | "loading" | "loaded" | "failed">(
    "idle"
  )
  const [errorMessage, setErrorMessage] = useState<string | null>(null)
  const [loadingMore, setLoadingMore] = useState(false)
  const [newFolderOpen, setNewFolderOpen] = useState(false)
  const [newFolderName, setNewFolderName] = useState("")
  const [renameTarget, setRenameTarget] = useState<VaultFolder | null>(null)
  const [renameName, setRenameName] = useState("")
  const [renameError, setRenameError] = useState<string | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<VaultFolder | null>(null)
  const loadMoreSentinelRef = useRef<HTMLDivElement | null>(null)

  const loadPage = useCallback(
    async (reset: boolean) => {
      if (reset) {
        setPhase((p) => (items.length === 0 ? "loading" : p))
        setErrorMessage(null)
      }
      try {
        const loadedFolders = await vault.refreshFolders()
        setFolders(loadedFolders)
        const page = await vaultListItems(
          supabase,
          filter,
          selectedFolderId,
          reset ? null : nextCursor,
          30
        )
        if (reset) {
          setItems(page.items)
        } else {
          setItems((prev) => {
            const ids = new Set(prev.map((i) => i.id))
            return [...prev, ...page.items.filter((i) => !ids.has(i.id))]
          })
        }
        setNextCursor(page.nextCursor)
        setPhase("loaded")
      } catch {
        if (reset && items.length === 0) {
          setPhase("failed")
          setErrorMessage("Couldn’t load Vault. Try again.")
        }
      }
    },
    [filter, items.length, nextCursor, selectedFolderId, vault]
  )

  useEffect(() => {
    void loadPage(true)
  }, [filter, selectedFolderId, vault.homeInvalidated]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    setFolders(vault.folders)
  }, [vault.folders])

  useEffect(() => {
    const node = loadMoreSentinelRef.current
    if (!node || !nextCursor || loadingMore) return
    const observer = new IntersectionObserver(
      (entries) => {
        if (!entries[0]?.isIntersecting) return
        setLoadingMore(true)
        void loadPage(false).finally(() => setLoadingMore(false))
      },
      { rootMargin: "160px" }
    )
    observer.observe(node)
    return () => observer.disconnect()
  }, [loadPage, loadingMore, nextCursor, items.length])

  const selectFilter = (next: VaultContentFilter) => {
    if (next === filter && selectedFolderId === null) return
    setFilter(next)
    setSelectedFolderId(null)
    setItems([])
    setNextCursor(null)
    setPhase("loading")
  }

  const selectFolder = (folder: VaultFolder) => {
    setSelectedFolderId((current) =>
      current === folder.id ? null : folder.id
    )
    setItems([])
    setNextCursor(null)
    setPhase("loading")
  }

  const openItem = async (item: VaultItem) => {
    const href = await resolveVaultItemHref(supabase, item)
    router.push(href)
  }

  const handleCreateFolder = async () => {
    const created = await vault.createFolder(newFolderName)
    if (created) {
      setNewFolderName("")
      setNewFolderOpen(false)
      setFolders([...vault.folders])
      void loadPage(true)
    }
  }

  const handleRename = async () => {
    if (!renameTarget) return
    const err = await vault.renameFolder(renameTarget.id, renameName)
    if (err) {
      setRenameError(err)
      return
    }
    setRenameTarget(null)
    setRenameName("")
    setRenameError(null)
    setFolders([...vault.folders])
  }

  const handleDeleteFolder = async () => {
    if (!deleteTarget) return
    const ok = await vault.deleteFolder(deleteTarget.id)
    if (ok) {
      if (selectedFolderId === deleteTarget.id) {
        setSelectedFolderId(null)
      }
      setDeleteTarget(null)
      void loadPage(true)
    }
  }

  return (
    <div className="tt-vault-home space-y-6" data-tt-native-surface>
      <p className="text-sm text-gray-400">
        Saved trades, posts, clips, and achievements — synced with the iOS app.
      </p>

      <div className="flex flex-wrap gap-2">
        {FILTERS.map((f) => {
          const selected = filter === f && selectedFolderId === null
          return (
            <button
              key={f}
              type="button"
              onClick={() => selectFilter(f)}
              className={`rounded-full px-3 py-1.5 text-xs font-medium transition ${
                selected
                  ? "bg-blue-500 text-white"
                  : "bg-white/10 text-gray-200 hover:bg-white/15"
              }`}
            >
              {vaultContentFilterLabel(f)}
            </button>
          )
        })}
      </div>

      <section className="space-y-3">
        <h3 className="text-base font-semibold text-white">Folders</h3>
        {folders.length === 0 ? (
          <p className="text-sm text-gray-500">
            Create folders to organize saved content.
          </p>
        ) : (
          <ul className="space-y-1">
            {folders.map((folder) => {
              const active = selectedFolderId === folder.id
              return (
                <li key={folder.id} className="group flex items-center gap-2">
                  <button
                    type="button"
                    onClick={() => selectFolder(folder)}
                    className={`flex min-w-0 flex-1 items-center gap-2 rounded-lg px-2 py-2 text-left text-sm transition ${
                      active
                        ? "bg-blue-500/15 text-blue-200"
                        : "text-gray-200 hover:bg-white/5"
                    }`}
                  >
                    <span className="text-gray-400" aria-hidden>
                      📁
                    </span>
                    <span className="truncate">{folder.name}</span>
                  </button>
                  <div className="flex shrink-0 gap-1 md:opacity-0 md:group-hover:opacity-100">
                    <button
                      type="button"
                      className="rounded px-2 py-1 text-xs text-gray-400 hover:bg-white/10 hover:text-white"
                      onClick={() => {
                        setRenameTarget(folder)
                        setRenameName(folder.name)
                        setRenameError(null)
                      }}
                    >
                      Rename
                    </button>
                    <button
                      type="button"
                      className="rounded px-2 py-1 text-xs text-red-400 hover:bg-white/10"
                      onClick={() => setDeleteTarget(folder)}
                    >
                      Delete
                    </button>
                  </div>
                </li>
              )
            })}
          </ul>
        )}
        <button
          type="button"
          className="inline-flex items-center gap-2 text-sm font-medium text-blue-400 hover:text-blue-300"
          onClick={() => setNewFolderOpen(true)}
        >
          New Folder
        </button>
      </section>

      <section className="space-y-3">
        <h3 className="text-base font-semibold text-white">
          {selectedFolderId ? "In Folder" : "Recent"}
        </h3>

        {phase === "loading" && items.length === 0 ? (
          <p className="py-8 text-center text-sm text-gray-500">Loading…</p>
        ) : null}

        {phase === "failed" && errorMessage ? (
          <div className="rounded-xl border border-red-500/30 bg-red-500/10 p-4 text-sm text-red-200">
            {errorMessage}
            <button
              type="button"
              className="ml-2 underline"
              onClick={() => void loadPage(true)}
            >
              Retry
            </button>
          </div>
        ) : null}

        {phase !== "loading" && items.length === 0 && phase !== "failed" ? (
          <div className="rounded-xl border border-white/10 bg-white/5 p-6 text-center">
            <VaultHexagonIcon filled className="mx-auto mb-2 h-8 w-8 text-blue-400" />
            <p className="font-medium text-white">Nothing saved yet</p>
            <p className="mt-1 text-sm text-gray-500">
              Tap the hexagon on posts, trades, clips, and achievements to add
              them here.
            </p>
          </div>
        ) : null}

        <ul className="space-y-2">
          {items.map((item) => (
            <li key={item.id}>
              <button
                type="button"
                onClick={() => void openItem(item)}
                className="flex w-full items-center gap-3 rounded-xl border border-white/10 bg-white/5 px-3 py-3 text-left transition hover:border-white/20 hover:bg-white/[0.07]"
              >
                <VaultHexagonIcon filled className="h-5 w-5 shrink-0 text-blue-400" />
                <div className="min-w-0 flex-1">
                  <p className="truncate font-medium text-white">
                    {vaultItemTitle(item.ref.contentType)}
                  </p>
                  <p className="truncate text-xs text-gray-500">
                    {vaultContentTypeLabel(item.ref.contentType)} ·{" "}
                    {relativeSavedAt(item.createdAt)}
                  </p>
                </div>
                <span className="shrink-0 text-gray-500" aria-hidden>
                  ›
                </span>
              </button>
            </li>
          ))}
        </ul>

        <div ref={loadMoreSentinelRef} className="h-1" aria-hidden />
        {loadingMore ? (
          <p className="py-2 text-center text-xs text-gray-500">Loading more…</p>
        ) : null}
      </section>

      <Modal
        open={newFolderOpen}
        onClose={() => setNewFolderOpen(false)}
        title="New Folder"
        size="sm"
      >
        <input
          value={newFolderName}
          onChange={(e) => setNewFolderName(e.target.value)}
          placeholder="Folder name"
          className="mb-3 w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-white"
          maxLength={64}
        />
        <Button
          disabled={normalizedVaultFolderName(newFolderName) == null}
          onClick={() => void handleCreateFolder()}
        >
          Create
        </Button>
      </Modal>

      <Modal
        open={renameTarget != null}
        onClose={() => setRenameTarget(null)}
        title="Rename Folder"
        size="sm"
      >
        <input
          value={renameName}
          onChange={(e) => setRenameName(e.target.value)}
          className="mb-2 w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-white"
          maxLength={64}
        />
        {renameError ? (
          <p className="mb-2 text-xs text-red-400">{renameError}</p>
        ) : null}
        <Button
          disabled={normalizedVaultFolderName(renameName) == null}
          onClick={() => void handleRename()}
        >
          Save
        </Button>
      </Modal>

      <Modal
        open={deleteTarget != null}
        onClose={() => setDeleteTarget(null)}
        title="Delete Folder?"
        size="sm"
        footer={
          <div className="flex justify-end gap-2">
            <Button variant="secondary" onClick={() => setDeleteTarget(null)}>
              Cancel
            </Button>
            <button
              type="button"
              className="rounded-lg bg-red-500/15 px-4 py-2 text-sm font-semibold text-red-300 hover:bg-red-500/25"
              onClick={() => void handleDeleteFolder()}
            >
              Delete
            </button>
          </div>
        }
      >
        <p className="text-sm text-gray-400">
          Items stay in your Vault; only the folder is removed.
        </p>
      </Modal>
    </div>
  )
}
