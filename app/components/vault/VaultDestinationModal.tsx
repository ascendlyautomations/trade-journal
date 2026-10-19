"use client"

import { useEffect, useState } from "react"
import Modal from "@/app/components/ui/Modal"
import Button from "@/app/components/ui/Button"
import { useVault } from "@/lib/vault/VaultProvider"
import type { VaultContentRef } from "@/lib/vault/types"
import { normalizedVaultFolderName } from "@/lib/vault/support"
import VaultHexagonIcon from "./VaultHexagonIcon"

type VaultDestinationModalProps = {
  open: boolean
  onClose: () => void
  ref: VaultContentRef
}

export default function VaultDestinationModal({
  open,
  onClose,
  ref: contentRef,
}: VaultDestinationModalProps) {
  const vault = useVault()
  const snap = vault.stateFor(contentRef)
  const [inFlight, setInFlight] = useState(false)
  const [showsNewFolder, setShowsNewFolder] = useState(false)
  const [newFolderName, setNewFolderName] = useState("")

  useEffect(() => {
    if (open) vault.loadFoldersIfNeeded()
  }, [open, vault])

  useEffect(() => {
    if (!open) {
      setShowsNewFolder(false)
      setNewFolderName("")
    }
  }, [open])

  const run = async (work: () => Promise<boolean | void>) => {
    if (inFlight) return
    setInFlight(true)
    try {
      const ok = await work()
      if (ok !== false) onClose()
    } finally {
      setInFlight(false)
    }
  }

  const membershipFolders = vault.folders.filter((f) =>
    snap.folderIDs.includes(f.id)
  )

  return (
    <Modal
      open={open}
      onClose={onClose}
      title={snap.isVaulted ? "Manage in Vault" : "Add to Vault"}
      size="md"
      belowNavbar
    >
      <div className="space-y-5 text-sm">
        {snap.isVaulted ? (
          <section className="space-y-2">
            <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">
              In Vault
            </h3>
            {membershipFolders.length === 0 ? (
              <p className="text-gray-400">Quick Save</p>
            ) : (
              <ul className="divide-y divide-white/10 rounded-xl border border-white/10">
                {membershipFolders.map((folder) => (
                  <li
                    key={folder.id}
                    className="flex items-center justify-between gap-3 px-3 py-2"
                  >
                    <span className="text-gray-100">{folder.name}</span>
                    <button
                      type="button"
                      disabled={inFlight}
                      className="text-xs font-semibold text-red-400 hover:text-red-300 disabled:opacity-50"
                      onClick={() =>
                        void run(() => vault.removeFromFolder(contentRef, folder.id))
                      }
                    >
                      Remove
                    </button>
                  </li>
                ))}
              </ul>
            )}
            <button
              type="button"
              disabled={inFlight}
              className="rounded-lg bg-red-500/15 px-3 py-2 text-sm font-medium text-red-300 hover:bg-red-500/25 disabled:opacity-50"
              onClick={() => void run(() => vault.removeFromVault(contentRef))}
            >
              Remove from Vault
            </button>
          </section>
        ) : (
          <section className="space-y-2">
            <Button
              variant="secondary"
              size="sm"
              disabled={inFlight}
              className="w-full justify-start gap-2"
              onClick={() => void run(() => vault.quickSave(contentRef))}
            >
              <VaultHexagonIcon filled className="h-4 w-4 text-blue-400" />
              Quick Save
            </Button>
            <p className="text-xs text-gray-500">
              Saves to your Vault without choosing a folder.
            </p>
          </section>
        )}

        <section className="space-y-2">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">
            Folders
          </h3>
          {vault.folders.length === 0 ? (
            <p className="text-xs text-gray-500">No folders yet</p>
          ) : (
            <ul className="divide-y divide-white/10 rounded-xl border border-white/10">
              {vault.folders.map((folder) => {
                const inFolder = snap.folderIDs.includes(folder.id)
                return (
                  <li key={folder.id}>
                    <button
                      type="button"
                      disabled={inFlight || inFolder}
                      className="flex w-full items-center justify-between gap-3 px-3 py-2.5 text-left text-gray-100 hover:bg-white/5 disabled:opacity-50"
                      onClick={() =>
                        void run(async () => {
                          if (snap.isVaulted) {
                            return vault.addToFolder(
                              contentRef,
                              folder.id,
                              folder.name
                            )
                          }
                          return vault.save(
                            contentRef,
                            folder.id,
                            `Added to ${folder.name}`
                          )
                        })
                      }
                    >
                      <span>{folder.name}</span>
                      {inFolder ? (
                        <span className="text-xs text-blue-400">✓</span>
                      ) : null}
                    </button>
                  </li>
                )
              })}
            </ul>
          )}
          <button
            type="button"
            className="text-sm font-medium text-blue-400 hover:text-blue-300"
            onClick={() => setShowsNewFolder((v) => !v)}
          >
            New Folder
          </button>
        </section>

        {showsNewFolder ? (
          <section className="space-y-2 rounded-xl border border-white/10 p-3">
            <label className="block text-xs text-gray-400" htmlFor="vault-new-folder">
              Folder name
            </label>
            <input
              id="vault-new-folder"
              value={newFolderName}
              onChange={(e) => setNewFolderName(e.target.value)}
              className="w-full rounded-lg border border-white/10 bg-white/5 px-3 py-2 text-sm text-white outline-none focus:ring-1 focus:ring-blue-400/50"
              maxLength={64}
            />
            <Button
              size="sm"
              disabled={
                inFlight || normalizedVaultFolderName(newFolderName) == null
              }
              onClick={() =>
                void run(async () => {
                  const folder = await vault.createFolder(newFolderName)
                  if (!folder) return false
                  setNewFolderName("")
                  setShowsNewFolder(false)
                  if (snap.isVaulted) {
                    return vault.addToFolder(
                      contentRef,
                      folder.id,
                      folder.name
                    )
                  }
                  return vault.save(
                    contentRef,
                    folder.id,
                    `Added to ${folder.name}`
                  )
                })
              }
            >
              Create and Save
            </Button>
          </section>
        ) : null}
      </div>
    </Modal>
  )
}
