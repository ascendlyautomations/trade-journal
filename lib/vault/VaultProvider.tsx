"use client"

import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react"
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

export function VaultProvider({ children }: { children: ReactNode }) {
  const toast = useToast()
  const [states, setStates] = useState<Record<string, VaultItemState>>({})
  const [folders, setFolders] = useState<VaultFolder[]>([])
  const foldersLoadedRef = useRef(false)
  const foldersTaskRef = useRef<Promise<void> | null>(null)
  const pendingPrefetchRef = useRef<Set<string>>(new Set())
  const loadedRefsRef = useRef<Set<string>>(new Set())
  const inFlightRef = useRef<Set<string>>(new Set())
  const [homeInvalidated, setHomeInvalidated] = useState(0)
  const userIdRef = useRef<string | null>(null)

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

  const pumpPrefetch = useCallback(async () => {
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
    if (batch.length === 0) return

    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (!user) return
    userIdRef.current = user.id

    const map = await vaultStateBatch(supabase, batch)
    setStates((prev) => {
      const next = { ...prev }
      map.forEach((value, key) => {
        next[key] = value
        loadedRefsRef.current.add(key)
      })
      return next
    })
  }, [])

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

      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return false
      userIdRef.current = user.id

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
        const item = await vaultSaveToVault(supabase, user.id, ref, folderId)
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
    [confirm, stateFor, toast]
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
      const {
        data: { user },
      } = await supabase.auth.getUser()
      if (!user) return null
      try {
        const folder = await vaultCreateFolder(supabase, user.id, name)
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
    [toast]
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
