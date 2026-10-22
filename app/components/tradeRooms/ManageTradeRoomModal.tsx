"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import CustomSelect from "@/app/components/CustomSelect"
import ModalCloseButton from "@/app/components/ui/ModalCloseButton"
import {
  TRADE_ROOM_CATEGORIES,
  TRADE_ROOM_PRESET_DISCOVERY_TAGS,
  TRADE_ROOM_VALIDATION,
  tradeRoomVisibilitySummary,
  validateTradeRoomConfiguration,
  type TradeRoomConfiguration,
  type TradeRoomJoinPolicy,
  type TradeRoomVisibility,
} from "@/lib/tradeRoomConfiguration"
import {
  assignMemberTag,
  createRoomMemberTag,
  deleteRoomMemberTag,
  deleteTradeRoom,
  ensureDefaultMemberTags,
  fetchMemberTagAssignments,
  fetchRoomMemberTags,
  listPendingTradeRoomJoinRequests,
  removeMemberTagAssignment,
  resolveTradeRoomJoinRequest,
  updateRoomMemberTag,
  updateTradeRoom,
  type RoomJoinRequest,
  type RoomMemberTag,
  type TradeRoomRow,
} from "@/lib/tradeRoomClient"
import {
  canDeleteTradeRoom,
  canManageTradeRoom,
} from "@/lib/tradeRoomManagementPermission"
import { supabase } from "@/lib/supabaseClient"
import { ProfileAvatarLink, ProfileUsernameLink } from "@/app/components/ProfileLink"

const FIELD =
  "w-full rounded-lg border border-white/10 bg-black/30 px-3 py-2.5 text-sm text-white placeholder:text-gray-400 focus:border-blue-400/45 focus:outline-none focus:ring-2 focus:ring-blue-500/25"
const LABEL = "mb-1.5 block text-xs font-medium text-gray-300"

const TAG_COLORS = [
  "accent",
  "blue",
  "green",
  "orange",
  "purple",
  "pink",
  "teal",
  "gray",
] as const

type Section = { id: string; name: string }

type TabId =
  | "details"
  | "channels"
  | "requests"
  | "tags"
  | "settings"

type Props = {
  open: boolean
  room: TradeRoomRow
  viewerId: string
  isPlatformAdmin: boolean
  isMember: boolean
  sections: Section[]
  onClose: () => void
  onRoomUpdated: (room: TradeRoomRow) => void
  onOpenManageMembers: () => void
  onOpenChannelSettings: (section: Section) => void
  onAddChannel: () => void
  onDeleted: () => void
  onLeaveRoom: () => void
}

function roomToDraft(room: TradeRoomRow): TradeRoomConfiguration {
  return {
    name: room.name ?? "",
    description: room.description ?? "",
    imageUrl: room.image_url ?? null,
    category: (room.category as TradeRoomConfiguration["category"]) ?? "general",
    discoveryTags: room.discovery_tags ?? [],
    visibility: room.is_private ? "private" : "public",
    showsOnProfile: room.show_on_profile !== false,
    joinPolicy: (room.join_policy as TradeRoomJoinPolicy) ?? "open",
    rules: room.rules ?? "",
    membersCanMessage: room.members_can_message !== false,
    membersCanShareTrades: room.members_can_share_trades !== false,
    membersCanShareMedia: room.members_can_share_media !== false,
    channels: [],
  }
}

export default function ManageTradeRoomModal({
  open,
  room,
  viewerId,
  isPlatformAdmin,
  isMember,
  sections,
  onClose,
  onRoomUpdated,
  onOpenManageMembers,
  onOpenChannelSettings,
  onAddChannel,
  onDeleted,
  onLeaveRoom,
}: Props) {
  const isOwner = room.owner_user_id === viewerId
  const canManage = canManageTradeRoom({
    viewerId,
    ownerUserId: room.owner_user_id,
    roomKind: room.room_kind,
    isPlatformAdmin,
  })

  const [tab, setTab] = useState<TabId>("details")
  const [draft, setDraft] = useState(() => roomToDraft(room))
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [joinRequests, setJoinRequests] = useState<RoomJoinRequest[]>([])
  const [loadingRequests, setLoadingRequests] = useState(false)
  const [tags, setTags] = useState<RoomMemberTag[]>([])
  const [, setAssignments] = useState<{ user_id: string; tag_id: string }[]>([])
  const [newTagName, setNewTagName] = useState("")
  const [newTagColor, setNewTagColor] = useState<string>("accent")

  const showsJoinRequests =
    !room.is_private && String(room.join_policy) === "approval"

  useEffect(() => {
    if (!open) return
    setDraft(roomToDraft(room))
    setTab("details")
    setError(null)
  }, [open, room])

  const loadTags = useCallback(async () => {
    await ensureDefaultMemberTags(supabase, room.id)
    const [nextTags, nextAssignments] = await Promise.all([
      fetchRoomMemberTags(supabase, room.id),
      fetchMemberTagAssignments(supabase, room.id),
    ])
    setTags(nextTags)
    setAssignments(nextAssignments)
  }, [room.id])

  const loadJoinRequests = useCallback(async () => {
    setLoadingRequests(true)
    const rows = await listPendingTradeRoomJoinRequests(supabase, room.id)
    setJoinRequests(rows)
    setLoadingRequests(false)
  }, [room.id])

  useEffect(() => {
    if (!open || !canManage) return
    if (tab === "requests" && showsJoinRequests) void loadJoinRequests()
    if (tab === "tags") void loadTags()
  }, [open, tab, canManage, showsJoinRequests, loadJoinRequests, loadTags])

  const tabs = useMemo(() => {
    const items: { id: TabId; label: string }[] = [
      { id: "details", label: "Details" },
      { id: "channels", label: "Channels" },
    ]
    if (showsJoinRequests) items.push({ id: "requests", label: "Join requests" })
    items.push({ id: "tags", label: "Tags" })
    items.push({ id: "settings", label: "Settings" })
    return items
  }, [showsJoinRequests])

  async function saveDetails() {
    setError(null)
    const validation = validateTradeRoomConfiguration(draft, { skipChannels: true })
    if (validation) {
      setError(validation)
      return
    }

    setSaving(true)
    const { room: updated, error: updErr } = await updateTradeRoom(supabase, room.id, {
      name: draft.name.trim(),
      description: draft.description.trim() || null,
      show_on_profile: draft.showsOnProfile,
      is_private: draft.visibility === "private",
      category: draft.category,
      discovery_tags: draft.discoveryTags,
      join_policy:
        draft.visibility === "private" ? "open" : draft.joinPolicy,
      rules: draft.rules.trim() || null,
      members_can_message: draft.membersCanMessage,
      members_can_share_trades: draft.membersCanShareTrades,
      members_can_share_media: draft.membersCanShareMedia,
    })
    setSaving(false)
    if (updErr || !updated) {
      setError(updErr ?? "Save failed")
      return
    }
    onRoomUpdated(updated)
  }

  function toggleDiscoveryTag(tag: string) {
    setDraft((prev) => {
      if (prev.discoveryTags.includes(tag)) {
        return { ...prev, discoveryTags: prev.discoveryTags.filter((t) => t !== tag) }
      }
      if (prev.discoveryTags.length >= TRADE_ROOM_VALIDATION.maxDiscoveryTags) return prev
      return { ...prev, discoveryTags: [...prev.discoveryTags, tag] }
    })
  }

  if (!open) return null

  if (!canManage && isMember && !isOwner) {
    return (
      <div className="fixed inset-0 z-[10055] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm">
        <div className="w-full max-w-md rounded-xl border border-white/10 bg-[#0f172a]/95 p-6 backdrop-blur-md">
          <h2 className="text-lg font-semibold text-blue-300">Trade Room settings</h2>
          <p className="mt-2 text-sm text-gray-400">Leave this room from settings below.</p>
          <button
            type="button"
            onClick={onLeaveRoom}
            className="mt-4 w-full rounded-lg border border-red-400/30 bg-red-500/10 py-2 text-sm text-red-200"
          >
            Leave room
          </button>
          <button type="button" onClick={onClose} className="mt-3 w-full text-sm text-gray-400">
            Close
          </button>
        </div>
      </div>
    )
  }

  if (!canManage) return null

  return (
    <div
      className="fixed inset-0 z-[10055] flex items-end justify-center bg-black/70 p-0 backdrop-blur-sm sm:items-center sm:p-4"
      onClick={onClose}
      role="presentation"
    >
      <div
        className="flex max-h-[min(90dvh,780px)] w-full max-w-3xl flex-col rounded-t-2xl border border-white/10 bg-[#0f172a]/95 shadow-2xl backdrop-blur-md sm:rounded-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start justify-between border-b border-white/10 px-5 py-4">
          <div>
            <p className="text-[11px] uppercase tracking-widest text-blue-300">Manage room</p>
            <h2 className="text-lg font-semibold text-white">{room.name ?? "Trade Room"}</h2>
          </div>
          <ModalCloseButton onClick={onClose} />
        </div>

        <div className="flex shrink-0 gap-1 overflow-x-auto border-b border-white/10 px-3 py-2">
          {tabs.map((t) => (
            <button
              key={t.id}
              type="button"
              onClick={() => setTab(t.id)}
              className={`shrink-0 rounded-lg px-3 py-1.5 text-xs font-medium ${
                tab === t.id
                  ? "bg-blue-500/20 text-blue-100"
                  : "text-gray-400 hover:bg-white/5"
              }`}
            >
              {t.label}
            </button>
          ))}
          <button
            type="button"
            onClick={() => {
              onOpenManageMembers()
              onClose()
            }}
            className="shrink-0 rounded-lg px-3 py-1.5 text-xs font-medium text-gray-400 hover:bg-white/5"
          >
            Members & bans
          </button>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-4">
          {tab === "details" ? (
            <div className="space-y-4">
              <div>
                <label className={LABEL}>Room name</label>
                <input
                  className={FIELD}
                  value={draft.name}
                  onChange={(e) => setDraft((p) => ({ ...p, name: e.target.value }))}
                />
              </div>
              <div>
                <label className={LABEL}>Description</label>
                <textarea
                  className={`${FIELD} min-h-[4rem]`}
                  value={draft.description}
                  onChange={(e) =>
                    setDraft((p) => ({ ...p, description: e.target.value }))
                  }
                />
              </div>
              <div>
                <label className={LABEL}>Category</label>
                <CustomSelect
                  value={draft.category}
                  onChange={(v) =>
                    setDraft((p) => ({
                      ...p,
                      category: v as TradeRoomConfiguration["category"],
                    }))
                  }
                  triggerClassName={`${FIELD} flex h-10 items-center justify-between`}
                  menuClassName="fixed z-[10070] max-h-60 overflow-y-auto rounded-lg border border-white/10 bg-[#0f172a]"
                  options={TRADE_ROOM_CATEGORIES.map((c) => ({
                    label: c.label,
                    value: c.value,
                  }))}
                />
              </div>
              <div>
                <p className="mb-2 text-xs text-gray-500">Discovery tags (up to 5)</p>
                <div className="flex flex-wrap gap-2">
                  {TRADE_ROOM_PRESET_DISCOVERY_TAGS.map((tag) => (
                    <button
                      key={tag}
                      type="button"
                      onClick={() => toggleDiscoveryTag(tag)}
                      className={`rounded-full border px-2 py-0.5 text-xs ${
                        draft.discoveryTags.includes(tag)
                          ? "border-blue-400/40 bg-blue-500/20 text-blue-100"
                          : "border-white/10 text-gray-400"
                      }`}
                    >
                      {tag}
                    </button>
                  ))}
                </div>
              </div>
              <div>
                <label className={LABEL}>Visibility</label>
                <div className="grid grid-cols-2 gap-2">
                  {(["public", "private"] as TradeRoomVisibility[]).map((v) => (
                    <button
                      key={v}
                      type="button"
                      onClick={() =>
                        setDraft((p) => ({
                          ...p,
                          visibility: v,
                          joinPolicy: v === "private" ? "open" : p.joinPolicy,
                        }))
                      }
                      className={`rounded-lg border px-3 py-2 text-sm capitalize ${
                        draft.visibility === v
                          ? "border-blue-400/40 bg-blue-500/15 text-blue-100"
                          : "border-white/10 text-gray-400"
                      }`}
                    >
                      {v}
                    </button>
                  ))}
                </div>
                <p className="mt-1 text-xs text-gray-500">
                  {tradeRoomVisibilitySummary(draft.visibility)}
                </p>
              </div>
              {draft.visibility === "public" ? (
                <div>
                  <label className={LABEL}>Join policy</label>
                  <div className="grid grid-cols-2 gap-2">
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
                          setDraft((p) => ({ ...p, joinPolicy: opt.value }))
                        }
                        className={`rounded-lg border px-3 py-2 text-xs ${
                          draft.joinPolicy === opt.value
                            ? "border-blue-400/40 bg-blue-500/15 text-blue-100"
                            : "border-white/10 text-gray-400"
                        }`}
                      >
                        {opt.label}
                      </button>
                    ))}
                  </div>
                </div>
              ) : null}
              <label className="flex items-center gap-2 text-sm text-gray-300">
                <input
                  type="checkbox"
                  checked={draft.showsOnProfile}
                  onChange={(e) =>
                    setDraft((p) => ({ ...p, showsOnProfile: e.target.checked }))
                  }
                />
                Show on my profile
              </label>
              <div>
                <label className={LABEL}>Room rules</label>
                <textarea
                  className={`${FIELD} min-h-[4rem]`}
                  value={draft.rules}
                  onChange={(e) => setDraft((p) => ({ ...p, rules: e.target.value }))}
                />
              </div>
              <div className="rounded-lg border border-white/10 bg-white/5 p-3">
                <p className="mb-2 text-xs font-semibold uppercase tracking-wide text-gray-400">
                  Member permissions
                </p>
                {(
                  [
                    ["membersCanMessage", "Members can send messages"],
                    ["membersCanShareTrades", "Members can share trades"],
                    ["membersCanShareMedia", "Members can share images/media"],
                  ] as const
                ).map(([key, label]) => (
                  <label key={key} className="mb-2 flex items-center gap-2 text-sm text-gray-300">
                    <input
                      type="checkbox"
                      checked={draft[key]}
                      onChange={(e) =>
                        setDraft((p) => ({ ...p, [key]: e.target.checked }))
                      }
                    />
                    {label}
                  </label>
                ))}
              </div>
              <button
                type="button"
                disabled={saving}
                onClick={() => void saveDetails()}
                className="rounded-lg bg-blue-500 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
              >
                {saving ? "Saving…" : "Save details"}
              </button>
            </div>
          ) : null}

          {tab === "channels" ? (
            <div className="space-y-2">
              {sections.map((section) => (
                <div
                  key={section.id}
                  className="flex items-center justify-between rounded-lg border border-white/10 bg-white/5 px-3 py-2"
                >
                  <span className="text-sm text-white">{section.name}</span>
                  <button
                    type="button"
                    onClick={() => onOpenChannelSettings(section)}
                    className="text-xs text-blue-300"
                  >
                    Edit
                  </button>
                </div>
              ))}
              <button
                type="button"
                onClick={onAddChannel}
                className="mt-2 text-sm text-blue-300"
              >
                + Add channel
              </button>
            </div>
          ) : null}

          {tab === "requests" && showsJoinRequests ? (
            <div className="space-y-2">
              {loadingRequests ? (
                <p className="text-sm text-gray-400">Loading…</p>
              ) : joinRequests.length === 0 ? (
                <p className="text-sm text-gray-400">No pending join requests.</p>
              ) : (
                joinRequests.map((req) => {
                  const profile = req.profiles
                  return (
                    <div
                      key={req.id}
                      className="flex items-center gap-3 rounded-lg border border-white/10 bg-white/5 p-2"
                    >
                      <ProfileAvatarLink
                        userId={req.user_id}
                        username={profile?.username ?? undefined}
                        src={profile?.avatar_url}
                        imgClassName="h-9 w-9 rounded-full"
                      />
                      <div className="min-w-0 flex-1">
                        <ProfileUsernameLink
                          userId={req.user_id}
                          username={profile?.username ?? undefined}
                          className="text-sm text-white"
                        />
                      </div>
                      <button
                        type="button"
                        className="rounded bg-emerald-500/20 px-2 py-1 text-xs text-emerald-200"
                        onClick={() =>
                          void resolveTradeRoomJoinRequest("approve", req.id).then(
                            () => loadJoinRequests()
                          )
                        }
                      >
                        Approve
                      </button>
                      <button
                        type="button"
                        className="rounded bg-red-500/20 px-2 py-1 text-xs text-red-200"
                        onClick={() =>
                          void resolveTradeRoomJoinRequest("decline", req.id).then(
                            () => loadJoinRequests()
                          )
                        }
                      >
                        Decline
                      </button>
                    </div>
                  )
                })
              )}
            </div>
          ) : null}

          {tab === "tags" ? (
            <div className="space-y-4">
              <p className="text-xs text-gray-500">
                Member tags for organizing your community (separate from Explore discovery tags).
              </p>
              <div className="flex flex-wrap gap-2">
                {tags.map((tag) => (
                  <span
                    key={tag.id}
                    className="rounded-full border border-white/10 bg-white/10 px-2 py-0.5 text-xs text-gray-200"
                  >
                    {tag.name}
                  </span>
                ))}
              </div>
              <div className="flex flex-wrap gap-2">
                <input
                  className={`${FIELD} max-w-[12rem]`}
                  placeholder="New tag name"
                  value={newTagName}
                  onChange={(e) => setNewTagName(e.target.value)}
                />
                <select
                  className={FIELD}
                  value={newTagColor}
                  onChange={(e) => setNewTagColor(e.target.value)}
                >
                  {TAG_COLORS.map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </select>
                <button
                  type="button"
                  className="rounded-lg bg-blue-500 px-3 py-2 text-xs text-white"
                  onClick={() => {
                    void createRoomMemberTag(
                      supabase,
                      room.id,
                      viewerId,
                      newTagName,
                      newTagColor
                    ).then(({ error: tagErr }) => {
                      if (tagErr) setError(tagErr)
                      else {
                        setNewTagName("")
                        void loadTags()
                      }
                    })
                  }}
                >
                  Create tag
                </button>
              </div>
              {tags.length > 0 ? (
                <div className="space-y-2">
                  {tags.map((tag) => (
                    <div
                      key={tag.id}
                      className="flex items-center justify-between rounded-lg border border-white/10 px-3 py-2"
                    >
                      <input
                        className="bg-transparent text-sm text-white outline-none"
                        defaultValue={tag.name}
                        onBlur={(e) => {
                          const name = e.target.value.trim()
                          if (!name || name === tag.name) return
                          void updateRoomMemberTag(supabase, {
                            ...tag,
                            name,
                          }).then(() => loadTags())
                        }}
                      />
                      <button
                        type="button"
                        className="text-xs text-red-400"
                        onClick={() => {
                          if (
                            !confirm(
                              "Delete this tag? It will be unassigned from members."
                            )
                          ) {
                            return
                          }
                          void deleteRoomMemberTag(supabase, room.id, tag.id).then(
                            () => loadTags()
                          )
                        }}
                      >
                        Delete
                      </button>
                    </div>
                  ))}
                </div>
              ) : null}
            </div>
          ) : null}

          {tab === "settings" ? (
            <div className="space-y-4">
              {canDeleteTradeRoom({
                viewerId,
                ownerUserId: room.owner_user_id,
                roomKind: room.room_kind,
              }) ? (
                <button
                  type="button"
                  className="w-full rounded-lg border border-red-400/30 bg-red-500/10 py-2 text-sm text-red-200"
                  onClick={() => {
                    if (
                      !confirm(
                        "Delete this Trade Room? This removes the room and its data for all members."
                      )
                    ) {
                      return
                    }
                    void deleteTradeRoom(supabase, room.id).then(({ error: delErr }) => {
                      if (delErr) setError(delErr)
                      else onDeleted()
                    })
                  }}
                >
                  Delete Trade Room
                </button>
              ) : (
                <p className="text-sm text-gray-400">
                  Official rooms cannot be deleted from settings.
                </p>
              )}
            </div>
          ) : null}

          {error ? (
            <p className="mt-3 text-sm text-red-300" role="alert">
              {error}
            </p>
          ) : null}
        </div>
      </div>
    </div>
  )
}

// Exported for member tag assignment from manage members (future hook-up)
export { assignMemberTag, removeMemberTagAssignment }
