"use client"

import { useEffect, useMemo, useState } from "react"
import ImageCropModal from "@/app/components/ImageCropModal"
import CustomSelect from "@/app/components/CustomSelect"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import { useImageCropUpload } from "@/lib/useImageCropUpload"
import { useUploadProgress } from "@/lib/uploadProgress/UploadProgressProvider"
import { supabase } from "@/lib/supabaseClient"
import { createTradeRoomViaRpc, type TradeRoomRow } from "@/lib/tradeRoomClient"
import { uploadTradeRoomImage } from "@/lib/tradeRoomImageUpload"
import {
  defaultTradeRoomDraft,
  TRADE_ROOM_CATEGORIES,
  TRADE_ROOM_PRESET_DISCOVERY_TAGS,
  TRADE_ROOM_VALIDATION,
  tradeRoomVisibilitySummary,
  validateTradeRoomConfiguration,
  type TradeRoomConfiguration,
  type TradeRoomDraftChannel,
  type TradeRoomJoinPolicy,
  type TradeRoomVisibility,
} from "@/lib/tradeRoomConfiguration"

const FIELD =
  "w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2.5 text-sm text-white placeholder:text-gray-400 focus:border-blue-400/45 focus:outline-none focus:ring-2 focus:ring-blue-500/25"
const LABEL = "mb-1.5 block text-xs font-medium text-gray-300"

type Props = {
  open: boolean
  userId: string
  username?: string | null
  ownedRoomSlug?: string | null
  onClose: () => void
  onCreated: (room: TradeRoomRow) => void
}

export default function TradeRoomCreateWizard({
  open,
  userId,
  username,
  ownedRoomSlug,
  onClose,
  onCreated,
}: Props) {
  const { runUpload } = useUploadProgress()
  const [config, setConfig] = useState<TradeRoomConfiguration>(() =>
    defaultTradeRoomDraft(username)
  )
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const [imagePreview, setImagePreview] = useState<string | null>(null)
  const [pendingImageFile, setPendingImageFile] = useState<File | null>(null)

  const imageCrop = useImageCropUpload({
    preset: "room",
    onCropped: (file) => {
      setPendingImageFile(file)
      setImagePreview(URL.createObjectURL(file))
    },
    onValidationError: setError,
  })

  useEffect(() => {
    if (!open) return
    setConfig(defaultTradeRoomDraft(username))
    setError(null)
    setImagePreview(null)
    setPendingImageFile(null)
  }, [open, username])

  const showsJoinPolicy = config.visibility === "public"

  const canSubmit = useMemo(() => {
    if (ownedRoomSlug) return false
    return config.name.trim().length > 0 && !submitting
  }, [config.name, ownedRoomSlug, submitting])

  function updateChannel(id: string, patch: Partial<TradeRoomDraftChannel>) {
    setConfig((prev) => ({
      ...prev,
      channels: prev.channels.map((ch) => (ch.id === id ? { ...ch, ...patch } : ch)),
    }))
  }

  function addChannel() {
    if (config.channels.length >= TRADE_ROOM_VALIDATION.maxChannels) return
    setConfig((prev) => ({
      ...prev,
      channels: [
        ...prev.channels,
        { id: crypto.randomUUID(), name: "", allowMembersChat: true },
      ],
    }))
  }

  function removeChannel(id: string) {
    setConfig((prev) => ({
      ...prev,
      channels: prev.channels.filter((ch) => ch.id !== id),
    }))
  }

  function moveChannel(id: string, direction: -1 | 1) {
    setConfig((prev) => {
      const idx = prev.channels.findIndex((ch) => ch.id === id)
      if (idx < 0) return prev
      const next = idx + direction
      if (next < 0 || next >= prev.channels.length) return prev
      const channels = [...prev.channels]
      const [item] = channels.splice(idx, 1)
      channels.splice(next, 0, item)
      return { ...prev, channels }
    })
  }

  function toggleDiscoveryTag(tag: string) {
    setConfig((prev) => {
      if (prev.discoveryTags.includes(tag)) {
        return {
          ...prev,
          discoveryTags: prev.discoveryTags.filter((t) => t !== tag),
        }
      }
      if (prev.discoveryTags.length >= TRADE_ROOM_VALIDATION.maxDiscoveryTags) {
        return prev
      }
      return { ...prev, discoveryTags: [...prev.discoveryTags, tag] }
    })
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    const validation = validateTradeRoomConfiguration(config)
    if (validation) {
      setError(validation)
      return
    }

    setSubmitting(true)
    try {
      let imageUrl = config.imageUrl
      if (pendingImageFile) {
        await runUpload({
          title: "Uploading room picture",
          execute: async (report) => {
            imageUrl = await uploadTradeRoomImage(
              supabase,
              userId,
              pendingImageFile,
              report
            )
          },
        })
      }

      const payload = { ...config, imageUrl }
      const { room, error: createError } = await createTradeRoomViaRpc(
        supabase,
        userId,
        payload
      )
      if (createError || !room) {
        setError(createError ?? "Failed to create room")
        return
      }
      onCreated(room)
    } catch (err) {
      console.error(err)
      setError(err instanceof Error ? err.message : "Failed to create room")
    } finally {
      setSubmitting(false)
    }
  }

  if (!open) return null

  return (
    <>
      <div
        className="fixed inset-0 z-[10060] flex items-end justify-center bg-black/70 p-0 backdrop-blur-sm sm:items-center sm:p-4"
        role="presentation"
        onClick={() => {
          if (submitting) return
          onClose()
        }}
      >
        <div
          className="flex max-h-[min(92dvh,820px)] w-full max-w-2xl flex-col rounded-t-2xl border border-white/10 bg-[#0f172a]/95 shadow-2xl backdrop-blur-md sm:rounded-2xl"
          onClick={(e) => e.stopPropagation()}
          role="dialog"
          aria-labelledby="create-trade-room-title"
        >
          <div className="flex shrink-0 items-start justify-between border-b border-white/10 px-5 py-4">
            <div>
              <p className="text-[11px] font-semibold uppercase tracking-[0.18em] text-blue-300">
                TradeTraxs
              </p>
              <h2 id="create-trade-room-title" className="text-lg font-semibold text-white">
                Create Trade Room
              </h2>
            </div>
            <ModalCloseButton onClick={onClose} disabled={submitting} />
          </div>

          {ownedRoomSlug ? (
            <div className="p-6 text-center">
              <p className="text-sm text-gray-300">You already have a Trade Room.</p>
              <button
                type="button"
                className="mt-4 rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white"
                onClick={onClose}
              >
                Go to your room
              </button>
            </div>
          ) : (
            <form
              onSubmit={(e) => void handleSubmit(e)}
              className="flex min-h-0 flex-1 flex-col"
            >
              <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
              <section className="mb-5">
                <h3 className="mb-3 text-sm font-semibold text-blue-200">Basic info</h3>
                <div className="space-y-3">
                  <div>
                    <label className={LABEL}>Room name *</label>
                    <input
                      className={FIELD}
                      value={config.name}
                      onChange={(e) =>
                        setConfig((p) => ({ ...p, name: e.target.value }))
                      }
                      placeholder="Room name"
                      maxLength={TRADE_ROOM_VALIDATION.nameMaxLength}
                    />
                  </div>
                  <div>
                    <label className={LABEL}>Description</label>
                    <textarea
                      className={`${FIELD} min-h-[4.5rem] resize-y`}
                      value={config.description}
                      onChange={(e) =>
                        setConfig((p) => ({ ...p, description: e.target.value }))
                      }
                      placeholder="Optional description"
                      maxLength={TRADE_ROOM_VALIDATION.descriptionMaxLength}
                    />
                  </div>
                  <div className="flex flex-wrap items-center gap-3">
                    {imagePreview ? (
                      // eslint-disable-next-line @next/next/no-img-element
                      <img
                        src={imagePreview}
                        alt=""
                        className="h-16 w-16 rounded-lg border border-white/10 object-cover"
                      />
                    ) : null}
                    <label className="cursor-pointer rounded-lg border border-white/10 bg-white/10 px-3 py-2 text-xs font-medium text-gray-200 hover:bg-white/15">
                      {imagePreview ? "Replace picture" : "Choose picture"}
                      <input
                        type="file"
                        accept="image/*"
                        className="sr-only"
                        onChange={(e) => {
                          imageCrop.handleFileSelected(e.target.files?.[0])
                          e.target.value = ""
                        }}
                      />
                    </label>
                    {imagePreview ? (
                      <button
                        type="button"
                        className="text-xs text-gray-400 hover:text-white"
                        onClick={() => {
                          setImagePreview(null)
                          setPendingImageFile(null)
                        }}
                      >
                        Remove picture
                      </button>
                    ) : null}
                  </div>
                </div>
              </section>

              <section className="mb-5">
                <h3 className="mb-3 text-sm font-semibold text-blue-200">Discovery</h3>
                <div className="grid gap-3 sm:grid-cols-2">
                  <div>
                    <label className={LABEL}>Category</label>
                    <CustomSelect
                      value={config.category}
                      onChange={(value) =>
                        setConfig((p) => ({
                          ...p,
                          category: value as TradeRoomConfiguration["category"],
                        }))
                      }
                      triggerClassName={`${FIELD} flex h-10 cursor-pointer items-center justify-between`}
                      menuClassName="fixed z-[10070] max-h-60 overflow-y-auto rounded-lg border border-white/10 bg-[#0f172a] shadow-lg"
                      options={TRADE_ROOM_CATEGORIES.map((c) => ({
                        label: c.label,
                        value: c.value,
                      }))}
                    />
                  </div>
                </div>
                <p className="mb-2 mt-3 text-xs text-gray-500">
                  Tags help traders find your room in Explore. Choose up to 5.
                </p>
                <div className="flex flex-wrap gap-2">
                  {TRADE_ROOM_PRESET_DISCOVERY_TAGS.map((tag) => {
                    const selected = config.discoveryTags.includes(tag)
                    return (
                      <button
                        key={tag}
                        type="button"
                        onClick={() => toggleDiscoveryTag(tag)}
                        className={`rounded-full border px-2.5 py-1 text-xs transition ${
                          selected
                            ? "border-blue-400/40 bg-blue-500/20 text-blue-100"
                            : "border-white/10 bg-white/5 text-gray-300 hover:bg-white/10"
                        }`}
                      >
                        {tag}
                      </button>
                    )
                  })}
                </div>
              </section>

              <section className="mb-5">
                <h3 className="mb-3 text-sm font-semibold text-blue-200">Access</h3>
                <div className="space-y-3">
                  <div>
                    <label className={LABEL}>Room visibility</label>
                    <div className="grid grid-cols-2 gap-2">
                      {(["public", "private"] as TradeRoomVisibility[]).map((v) => (
                        <button
                          key={v}
                          type="button"
                          onClick={() =>
                            setConfig((p) => ({
                              ...p,
                              visibility: v,
                              joinPolicy: v === "private" ? "open" : p.joinPolicy,
                            }))
                          }
                          className={`rounded-lg border px-3 py-2 text-sm capitalize ${
                            config.visibility === v
                              ? "border-blue-400/40 bg-blue-500/15 text-blue-100"
                              : "border-white/10 bg-white/5 text-gray-300"
                          }`}
                        >
                          {v}
                        </button>
                      ))}
                    </div>
                    <p className="mt-2 text-xs text-gray-500">
                      {tradeRoomVisibilitySummary(config.visibility)}
                    </p>
                  </div>

                  {showsJoinPolicy ? (
                    <div>
                      <label className={LABEL}>Join policy</label>
                      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
                        {(
                          [
                            { value: "open", label: "Anyone can join" },
                            { value: "approval", label: "Request to join" },
                          ] as const
                        ).map((opt) => (
                          <button
                            key={opt.value}
                            type="button"
                            onClick={() =>
                              setConfig((p) => ({
                                ...p,
                                joinPolicy: opt.value as TradeRoomJoinPolicy,
                              }))
                            }
                            className={`rounded-lg border px-3 py-2 text-left text-sm ${
                              config.joinPolicy === opt.value
                                ? "border-blue-400/40 bg-blue-500/15 text-blue-100"
                                : "border-white/10 bg-white/5 text-gray-300"
                            }`}
                          >
                            {opt.label}
                          </button>
                        ))}
                      </div>
                    </div>
                  ) : null}

                  <label className="flex items-start gap-2 text-sm text-gray-300">
                    <input
                      type="checkbox"
                      checked={config.showsOnProfile}
                      onChange={(e) =>
                        setConfig((p) => ({ ...p, showsOnProfile: e.target.checked }))
                      }
                      className="mt-1"
                    />
                    <span>
                      <span className="font-medium text-white">Show on my profile</span>
                      <span className="mt-1 block text-xs text-gray-500">
                        Profile visibility is separate — hiding from your profile does not
                        make the room private.
                      </span>
                    </span>
                  </label>
                </div>
              </section>

              <section className="mb-5">
                <h3 className="mb-3 text-sm font-semibold text-blue-200">Sub-rooms</h3>
                <p className="mb-3 text-xs text-gray-500">
                  Each sub-room has its own post permissions. Room-wide trade and media
                  sharing use defaults until you edit the room later.
                </p>
                <div className="space-y-2">
                  {config.channels.map((channel, index) => (
                    <div
                      key={channel.id}
                      className="rounded-lg border border-white/10 bg-white/5 p-3"
                    >
                      <input
                        className={FIELD}
                        value={channel.name}
                        onChange={(e) =>
                          updateChannel(channel.id, { name: e.target.value })
                        }
                        placeholder="Sub-room name"
                      />
                      <label className="mt-2 flex items-center gap-2 text-xs text-gray-300">
                        <input
                          type="checkbox"
                          checked={channel.allowMembersChat}
                          onChange={(e) =>
                            updateChannel(channel.id, {
                              allowMembersChat: e.target.checked,
                            })
                          }
                        />
                        Members can post in this sub-room
                      </label>
                      <div className="mt-2 flex gap-2">
                        <button
                          type="button"
                          disabled={index === 0}
                          onClick={() => moveChannel(channel.id, -1)}
                          className="text-xs text-gray-400 disabled:opacity-40"
                        >
                          Move up
                        </button>
                        <button
                          type="button"
                          disabled={index === config.channels.length - 1}
                          onClick={() => moveChannel(channel.id, 1)}
                          className="text-xs text-gray-400 disabled:opacity-40"
                        >
                          Move down
                        </button>
                        {config.channels.length > 1 ? (
                          <button
                            type="button"
                            onClick={() => removeChannel(channel.id)}
                            className="text-xs text-red-400"
                          >
                            Delete
                          </button>
                        ) : null}
                      </div>
                    </div>
                  ))}
                </div>
                {config.channels.length < TRADE_ROOM_VALIDATION.maxChannels ? (
                  <button
                    type="button"
                    onClick={addChannel}
                    className="mt-2 text-sm text-blue-300 hover:text-blue-200"
                  >
                    + Add sub-room
                  </button>
                ) : null}
              </section>

              <section className="mb-4">
                <h3 className="mb-3 text-sm font-semibold text-blue-200">Room rules</h3>
                <textarea
                  className={`${FIELD} min-h-[5rem] resize-y`}
                  value={config.rules}
                  onChange={(e) => setConfig((p) => ({ ...p, rules: e.target.value }))}
                  placeholder="Optional guidelines for members"
                  maxLength={TRADE_ROOM_VALIDATION.rulesMaxLength}
                />
              </section>

              {error ? (
                <p className="mb-3 rounded-lg border border-red-500/30 bg-red-950/40 px-3 py-2 text-sm text-red-200">
                  {error}
                </p>
              ) : null}
              </div>
              <div className="shrink-0 border-t border-white/10 px-5 py-4">
                <button
                  type="submit"
                  disabled={!canSubmit}
                  className="w-full rounded-lg bg-blue-500 py-2.5 text-sm font-semibold text-white disabled:opacity-50"
                >
                  {submitting ? "Creating…" : "Create Trade Room"}
                </button>
              </div>
            </form>
          )}
        </div>
      </div>
      <ImageCropModal
        open={imageCrop.cropSourceFile != null}
        file={imageCrop.cropSourceFile}
        preset="room"
        onCancel={imageCrop.handleCropCancel}
        onSave={imageCrop.handleCropSave}
      />
    </>
  )
}
