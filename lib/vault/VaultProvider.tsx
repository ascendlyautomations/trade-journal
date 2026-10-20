"use client"

import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react"
import { useUserProfile } from "@/lib/UserProfileProvider"
import { supabase } from "@/lib/supabaseClient"
import { useToast } from "@/app/components/ui"
import {
  vaultAddToFolder,
  vaultCreateFolder,
  vaultDeleteFolder,
  vaultListFolders,
  vaultRemoveFromFolder,
  vaultRemoveFromVault,
  vaultRenameFolder,
  vaultSaveToVault,
  vaultStateBatch,
} from "./repository"
import type { VaultContentRef, VaultFolder, VaultItemState } from "./types"
import { VAULT_NOT_SAVED, vaultRefKey } from "./types"
import { mapVaultFolderMutationError, normalizedVaultFolderName } from "./support"

type VaultContextValue = {
  folders: VaultFolder[]
  stateFor: (ref: VaultContentRef) => VaultItemState
  prefetch: (refs: VaultContentRef[]) => void
  loadFoldersIfNeeded: () => void
  refreshFolders: () => Promise<VaultFolder[]>
  quickSave: (ref: VaultContentRef) => Promise<boolean>
  save: (
    ref: VaultContentRef,
    folderId: string | null,
    confirmation: string
  ) => Promise<boolean>
  addToFolder: (
    ref: VaultContentRef,
    folderId: string,
    folderName: string
  ) => Promise<boolean>
  removeFromFolder: (ref: VaultContentRef, folderId: string) => Promise<boolean>
  removeFromVault: (ref: VaultContentRef) => Promise<boolean>
  createFolder: (name: string) => Promise<VaultFolder | null>
  renameFolder: (folderId: string, name: string) => Promise<string | null>
  deleteFolder: (folderId: string) => Promise<boolean>
  invalidateHomeList: () => void
  homeInvalidated: number
}

const VaultContext = createContext<VaultContextValue | null>(null)

function isAuthLockAbortError(error: unknown): boolean {
  if (!error || typeof error !== "object") return false
  const name = "name" in error ? String(error.name) : ""
  if (name === "AbortError") return true
  const message = "message" in error ? String(error.message) : ""
  return message.includes("Lock broken") || message.includes("steal")
}

export function VaultProvider({ children }: { children: ReactNode }) {
  const toast = useToast()
  const { user } = useUserProfile()
  const [states, setStates] = useState<Record<string, VaultItemState>>({})
  const [folders, setFolders] = useState<VaultFolder[]>([])
  const foldersLoadedRef = useRef(false)
  const foldersTaskRef = useRef<Promise<void> | null>(null)
  const pendingPrefetchRef = useRef<Set<string>>(new Set())
  const loadedRefsRef = useRef<Set<string>>(new Set())
  const inFlightRef = useRef<Set<string>>(new Set())
  const prefetchPumpRef = useRef<Promise<void> | null>(null)
  const sessionUserReadRef = useRef<Promise<string | null> | null>(null)
  const [homeInvalidated, setHomeInvalidated] = useState(0)
  const userIdRef = useRef<string | null>(null)

  const readActorUserId = useCallback(async (): Promise<string | null> => {
    if (user?.id) {
      userIdRef.current = user.id
      return user.id
    }
    if (userIdRef.current) return userIdRef.current
    if (sessionUserReadRef.current) return sessionUserReadRef.current

    sessionUserReadRef.current = (async () => {
      try {
        const { data, error } = await supabase.auth.getSession()
        if (error) throw error
        const id = data.session?.user?.id ?? null
        if (id) userIdRef.current = id
        return id
      } catch (error) {
        if (isAuthLockAbortError(error)) {
          await new Promise((resolve) => setTimeout(resolve, 32))
          try {
            const { data } = await supabase.auth.getSession()
            const id = data.session?.user?.id ?? null
            if (id) userIdRef.current = id
            return id
          } catch {
            return null
          }
        }
        return null
      } finally {
        sessionUserReadRef.current = null
      }
    })()

    return sessionUserReadRef.current
  }, [user?.id])

  const confirm = useCallback(
    (message: string) => {
      toast.success(message)
    },
    [toast]
  )

  const stateFor = useCallback(
    (ref: VaultContentRef): VaultItemState => {
      return states[vaultRefKey(ref)] ?? VAULT_NOT_SAVED
    },
    [states]
  )

  const takePendingPrefetchBatch = useCallback((): VaultContentRef[] => {
    const batch: VaultContentRef[] = []
    for (const key of pendingPrefetchRef.current) {
      const [contentType, ...rest] = key.split(":")
      const contentID = rest.join(":")
      batch.push({
        contentType: contentType as VaultContentRef["contentType"],
        contentID,
      })
      pendingPrefetchRef.current.delete(key)
    }
    return batch
  }, [])

  const pumpPrefetch = useCallback(async () => {
    if (prefetchPumpRef.current) {
      await prefetchPumpRef.current
      return
    }

    const task = (async () => {
      for (;;) {
        const batch = takePendingPrefetchBatch()
        if (batch.length === 0) break

        const actorId = user?.id ?? userIdRef.current ?? (await readActorUserId())
        if (!actorId) {
          for (const ref of batch) {
            pendingPrefetchRef.current.add(vaultRefKey(ref))
          }
          break
        }
        userIdRef.current = actorId

        try {
          const map = await vaultStateBatch(supabase, batch)
          setStates((prev) => {
            const next = { ...prev }
            map.forEach((value, key) => {
              next[key] = value
              loadedRefsRef.current.add(key)
            })
            return next
          })
        } catch {
          // soft-fail; refs stay unloaded until a later prefetch
        }
      }
    })()

    prefetchPumpRef.current = task.finally(() => {
      prefetchPumpRef.current = null
      if (pendingPrefetchRef.current.size > 0) {
        void pumpPrefetch()
      }
    })
    await prefetchPumpRef.current
  }, [readActorUserId, takePendingPrefetchBatch, user?.id])

  useEffect(() => {
    if (!user?.id) return
    userIdRef.current = user.id
    if (pendingPrefetchRef.current.size > 0) {
      void pumpPrefetch()
    }
  }, [pumpPrefetch, user?.id])

  const prefetch = useCallback(
    (refs: VaultContentRef[]) => {
      for (const ref of refs) {
        const key = vaultRefKey(ref)
        if (loadedRefsRef.current.has(key)) continue
        pendingPrefetchRef.current.add(key)
      }
      void pumpPrefetch()
    },
    [pumpPrefetch]
  )

  const loadFoldersIfNeeded = useCallback(() => {
    if (foldersLoadedRef.current || foldersTaskRef.current) return
    foldersTaskRef.current = (async () => {
      try {
        const loaded = await vaultListFolders(supabase)
        setFolders(loaded)
        foldersLoadedRef.current = true
      } catch {
        // soft-fail
      } finally {
        foldersTaskRef.current = null
      }
    })()
  }, [])

  const refreshFolders = useCallback(async (): Promise<VaultFolder[]> => {
    try {
      const loaded = await vaultListFolders(supabase)
      setFolders(loaded)
      foldersLoadedRef.current = true
      return loaded
    } catch {
      toast.error("Could not load folders.")
      return []
    }
  }, [toast])

  const save = useCallback(
    async (
      ref: VaultContentRef,
      folderId: string | null,
      confirmation: string
    ): Promise<boolean> => {
      const key = vaultRefKey(ref)
      if (inFlightRef.current.has(key)) return false

      const userId = await readActorUserId()
      if (!userId) return false

      const previous = stateFor(ref)
      inFlightRef.current.add(key)
      const optimistic: VaultItemState = {
        isVaulted: true,
        vaultItemID: previous.vaultItemID ?? crypto.randomUUID(),
        folderIDs:
          folderId && !previous.folderIDs.includes(folderId)
            ? [...previous.folderIDs, folderId]
            : previous.folderIDs,
      }
      setStates((s) => ({ ...s, [key]: optimistic }))

      try {
        const item = await vaultSaveToVault(supabase, userId, ref, folderId)
        setStates((s) => ({
          ...s,
          [key]: {
            isVaulted: true,
            vaultItemID: item.id,
            folderIDs: item.folderIDs,
          },
        }))
        loadedRefsRef.current.add(key)
        setHomeInvalidated((n) => n + 1)
        confirm(confirmation)
        return true
      } catch {
        setStates((s) => ({ ...s, [key]: previous }))
        toast.error("Could not save to Vault.")
        return false
      } finally {
        inFlightRef.current.delete(key)
      }
    },
    [confirm, readActorUserId, stateFor, toast]
  )

  const quickSave = useCallback(
    (ref: VaultContentRef) => save(ref, null, "Added to Vault"),
    [save]
  )

  const addToFolder = useCallback(
    async (
      ref: VaultContentRef,
      folderId: string,
      folderName: string
    ): Promise<boolean> => {
      const snap = stateFor(ref)
      if (!snap.isVaulted || !snap.vaultItemID) {
        return save(ref, folderId, `Added to ${folderName}`)
      }
      const key = vaultRefKey(ref)
      if (inFlightRef.current.has(key)) return false
      inFlightRef.current.add(key)
      const previous = snap
      const optimistic: VaultItemState = {
        ...snap,
        folderIDs: snap.folderIDs.includes(folderId)
          ? snap.folderIDs
          : [...snap.folderIDs, folderId],
      }
      setStates((s) => ({ ...s, [key]: optimistic }))
      try {
        await vaultAddToFolder(supabase, snap.vaultItemID, folderId)
        confirm(`Added to ${folderName}`)
        setHomeInvalidated((n) => n + 1)
        return true
      } catch {
        setStates((s) => ({ ...s, [key]: previous }))
        toast.error("Could not add to folder.")
        return false
      } finally {
        inFlightRef.current.delete(key)
      }
    },
    [confirm, save, stateFor, toast]
  )

  const removeFromFolder = useCallback(
    async (ref: VaultContentRef, folderId: string): Promise<boolean> => {
      const snap = stateFor(ref)
      if (!snap.vaultItemID) return false
      const key = vaultRefKey(ref)
      if (inFlightRef.current.has(key)) return false
      inFlightRef.current.add(key)
      const previous = snap
      setStates((s) => ({
        ...s,
        [key]: {
          ...snap,
          folderIDs: snap.folderIDs.filter((id) => id !== folderId),
        },
      }))
      try {
        await vaultRemoveFromFolder(supabase, snap.vaultItemID, folderId)
        confirm("Removed from folder")
        setHomeInvalidated((n) => n + 1)
        return true
      } catch {
        setStates((s) => ({ ...s, [key]: previous }))
        toast.error("Could not remove from folder.")
        return false
      } finally {
        inFlightRef.current.delete(key)
      }
    },
    [confirm, stateFor, toast]
  )

  const removeFromVault = useCallback(
    async (ref: VaultContentRef): Promise<boolean> => {
      const snap = stateFor(ref)
      if (!snap.vaultItemID) return false
      const key = vaultRefKey(ref)
      if (inFlightRef.current.has(key)) return false
      inFlightRef.current.add(key)
      const previous = snap
      setStates((s) => ({ ...s, [key]: VAULT_NOT_SAVED }))
      try {
        await vaultRemoveFromVault(supabase, snap.vaultItemID)
        setHomeInvalidated((n) => n + 1)
        confirm("Removed from Vault")
        return true
      } catch {
        setStates((s) => ({ ...s, [key]: previous }))
        toast.error("Could not remove from Vault.")
        return false
      } finally {
        inFlightRef.current.delete(key)
      }
    },
    [confirm, stateFor, toast]
  )

  const createFolder = useCallback(
    async (name: string): Promise<VaultFolder | null> => {
      if (!normalizedVaultFolderName(name)) return null
      const userId = await readActorUserId()
      if (!userId) return null
      try {
        const folder = await vaultCreateFolder(supabase, userId, name)
        setFolders((prev) =>
          [...prev, folder].sort((a, b) =>
            a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
          )
        )
        foldersLoadedRef.current = true
        return folder
      } catch (error) {
        toast.error(mapVaultFolderMutationError(error))
        return null
      }
    },
    [readActorUserId, toast]
  )

  const renameFolder = useCallback(
    async (folderId: string, rawName: string): Promise<string | null> => {
      const normalized = normalizedVaultFolderName(rawName)
      if (!normalized) return "Folder name cannot be empty."
      const existing = folders.find((f) => f.id === folderId)
      if (existing && existing.name === normalized) return null
      try {
        const updated = await vaultRenameFolder(supabase, folderId, normalized)
        setFolders((prev) =>
          prev
            .map((f) => (f.id === folderId ? updated : f))
            .sort((a, b) =>
              a.name.localeCompare(b.name, undefined, { sensitivity: "base" })
            )
        )
        await refreshFolders()
        return null
      } catch (error) {
        return mapVaultFolderMutationError(error)
      }
    },
    [folders, refreshFolders]
  )

  const deleteFolder = useCallback(
    async (folderId: string): Promise<boolean> => {
      try {
        await vaultDeleteFolder(supabase, folderId)
        setFolders((prev) => prev.filter((f) => f.id !== folderId))
        setStates((prev) => {
          const next = { ...prev }
          for (const [key, state] of Object.entries(next)) {
            if (!state.isVaulted) continue
            next[key] = {
              ...state,
              folderIDs: state.folderIDs.filter((id) => id !== folderId),
            }
          }
          return next
        })
        setHomeInvalidated((n) => n + 1)
        return true
      } catch {
        toast.error("Could not delete folder.")
        return false
      }
    },
    [toast]
  )

  const invalidateHomeList = useCallback(() => {
    setHomeInvalidated((n) => n + 1)
  }, [])

  const value = useMemo(
    () => ({
      folders,
      stateFor,
      prefetch,
      loadFoldersIfNeeded,
      refreshFolders,
      quickSave,
      save,
      addToFolder,
      removeFromFolder,
      removeFromVault,
      createFolder,
      renameFolder,
      deleteFolder,
      invalidateHomeList,
      homeInvalidated,
    }),
    [
      folders,
      stateFor,
      prefetch,
      loadFoldersIfNeeded,
      refreshFolders,
      quickSave,
      save,
      addToFolder,
      removeFromFolder,
      removeFromVault,
      createFolder,
      renameFolder,
      deleteFolder,
      invalidateHomeList,
      homeInvalidated,
    ]
  )

  return <VaultContext.Provider value={value}>{children}</VaultContext.Provider>
}

export function useVault(): VaultContextValue {
  const ctx = useContext(VaultContext)
  if (!ctx) {
    throw new Error("useVault must be used within VaultProvider")
  }
  return ctx
}
