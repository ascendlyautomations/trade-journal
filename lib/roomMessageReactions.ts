/** V1 message reactions — DMs (`message_reactions`) + Trade Rooms (`room_message_reactions`). */

import {
  MESSAGE_REACTION_QUICK_PICKS,
  isValidMessageReaction,
  normalizeMessageReaction,
} from "@/lib/messageReactionValidation"

export const ROOM_MESSAGE_REACTIONS = MESSAGE_REACTION_QUICK_PICKS

export const MESSAGE_REACTIONS = ROOM_MESSAGE_REACTIONS

/** Double-tap adds/removes this reaction (not thumbs-up). */
export const MESSAGE_REACTION_DOUBLE_TAP_EMOJI = MESSAGE_REACTION_QUICK_PICKS[0]

/** Tail padding so bubble-attached reaction chips do not shift timestamps. */
export const MESSAGE_REACTION_BUBBLE_RESERVE_CLASS = "pb-5"

export type RoomMessageReactionEmoji = string

export type MessageReactionEmoji = RoomMessageReactionEmoji

export type RoomMessageReactionRow = {
  id: string
  message_id: string
  user_id: string
  reaction: string
  created_at?: string
}

/** Same row shape for DM and Trade Room reaction tables. */
export type MessageReactionRow = RoomMessageReactionRow

export type RoomMessageReactionSummary = {
  emoji: string
  count: number
  reactedByViewer: boolean
}

export function aggregateRoomMessageReactions(
  reactions: RoomMessageReactionRow[] | null | undefined,
  viewerUserId: string | null | undefined
): RoomMessageReactionSummary[] {
  const counts = new Map<string, number>()
  let viewerEmoji: string | null = null

  for (const row of reactions ?? []) {
    const emoji = normalizeMessageReaction(row.reaction)
    if (!emoji || !isValidMessageReaction(emoji)) continue
    counts.set(emoji, (counts.get(emoji) ?? 0) + 1)
    if (viewerUserId && row.user_id === viewerUserId) {
      viewerEmoji = emoji
    }
  }

  return [...counts.entries()]
    .sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0]))
    .map(([emoji, count]) => ({
      emoji,
      count,
      reactedByViewer: viewerEmoji === emoji,
    }))
}

export function shouldReserveMessageReactionBubbleSpace(
  reactions: RoomMessageReactionRow[] | null | undefined,
  viewerUserId: string | null | undefined,
  canReact: boolean
): boolean {
  if (!canReact) {
    return aggregateRoomMessageReactions(reactions, viewerUserId).length > 0
  }
  return true
}

export function patchRoomMessageReactions(
  reactions: RoomMessageReactionRow[] | null | undefined,
  next: RoomMessageReactionRow,
  mode: "insert" | "delete"
): RoomMessageReactionRow[] {
  const list = reactions ?? []
  if (mode === "insert") {
    const emoji = normalizeMessageReaction(next.reaction)
    if (!emoji) return list
    const withoutViewer = list.filter((row) => row.user_id !== next.user_id)
    if (withoutViewer.some((row) => row.id === next.id)) {
      return withoutViewer
    }
    return [...withoutViewer, { ...next, reaction: emoji }]
  }

  return list.filter((row) => row.id !== next.id)
}