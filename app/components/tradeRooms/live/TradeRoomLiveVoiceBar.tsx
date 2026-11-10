"use client"

import { ConnectionState } from "livekit-client"
import { useRouter } from "next/navigation"
import {
  ChevronDown,
  ChevronUp,
  Headphones,
  Mic,
  MicOff,
  PhoneOff,
  Users,
} from "lucide-react"
import { useEffect, useMemo, useState, useSyncExternalStore } from "react"
import TradeRoomLiveParticipantModerationMenu from "./TradeRoomLiveParticipantModerationMenu.tsx"
import TradeRoomLiveModerationErrorNote from "./TradeRoomLiveModerationErrorNote.tsx"
import {
  getTradeRoomLiveModerationUiContextSnapshot,
  moderationUiCanActOnMember,
  subscribeTradeRoomLiveModerationUiContext,
} from "@/lib/livekit/client/tradeRoomLiveModerationUiContext.ts"
import { SafeProfileAvatar } from "@/app/components/SafeProfileAvatar.tsx"
import { supabase } from "@/lib/supabaseClient.ts"
import type { LiveVoiceParticipantView } from "@/lib/livekit/client/tradeRoomLiveVoiceStore.ts"
import { useTradeRoomLiveVoice } from "./useTradeRoomLiveVoice.ts"

function initialsFromDisplayName(name: string): string {
  const trimmed = name.trim()
  if (!trimmed) return "?"
  const parts = trimmed.split(/\s+/).filter(Boolean)
  if (parts.length === 1) {
    return parts[0].slice(0, 2).toUpperCase()
  }
  const a = parts[0][0] ?? ""
  const b = parts[parts.length - 1][0] ?? ""
  return (a + b).toUpperCase() || "?"
}

function avatarHueFromIdentity(identity: string): number {
  let h = 0
  for (let i = 0; i < identity.length; i += 1) {
    h = (h + identity.charCodeAt(i) * (i + 1)) % 360
  }
  return h
}

function VoiceParticipantAvatar({
  participant,
  sizeClass,
  avatarUrl,
}: {
  participant: LiveVoiceParticipantView
  sizeClass: string
  avatarUrl?: string | null
}) {
  const initials = initialsFromDisplayName(participant.name)
  const hue = avatarHueFromIdentity(participant.identity)
  /** Stable ring — do not tie layout to LiveKit active-speaker (avoids reflow in trade room). */
  const ring = "ring-2 ring-white/15 ring-offset-2 ring-offset-zinc-950"
  const fallback = (
    <div
      className="flex h-full w-full items-center justify-center font-semibold text-white/95 shadow-inner"
      style={{
        backgroundColor: `hsla(${hue}, 42%, 38%, 0.9)`,
      }}
    >
      <span className="select-none leading-none">{initials}</span>
    </div>
  )
  return (
    <div className="shrink-0" title={participant.name} aria-hidden>
      <SafeProfileAvatar
        src={avatarUrl ?? null}
        alt=""
        className={`${sizeClass} ${ring}`}
        fallback={fallback}
      />
    </div>
  )
}

function connectionStatusLabel(
  state: ConnectionState,
  canPublish: boolean,
  isBusy: boolean
): string {
  if (isBusy) return "Updating…"
  switch (state) {
    case ConnectionState.Connected:
      return canPublish ? "Connected · Mic" : "Connected · Listen only"
    case ConnectionState.Connecting:
      return "Connecting…"
    case ConnectionState.Reconnecting:
      return "Reconnecting…"
    case ConnectionState.SignalReconnecting:
      return "Reconnecting…"
    case ConnectionState.Disconnected:
      return "Disconnected"
    default:
      return "Voice"
  }
}

type TradeRoomLiveVoiceBarProps = {
  placement?: "fixed" | "embedded" | "shell"
}

export default function TradeRoomLiveVoiceBar({
  placement = "fixed",
}: TradeRoomLiveVoiceBarProps) {
  const router = useRouter()
  const voice = useTradeRoomLiveVoice()
  const moderationCtx = useSyncExternalStore(
    subscribeTradeRoomLiveModerationUiContext,
    getTradeRoomLiveModerationUiContextSnapshot,
    getTradeRoomLiveModerationUiContextSnapshot
  )
  const [minimized, setMinimized] = useState(false)
  const [membersOpen, setMembersOpen] = useState(false)
  const [voiceAvatarByUserId, setVoiceAvatarByUserId] = useState<
    Record<string, string | null>
  >({})
  const [moderationError, setModerationError] = useState<string | null>(null)

  const participantIdSignature = useMemo(() => {
    const ids = [
      ...new Set(
        voice.participants.map((p) => p.identity).filter((id): id is string => Boolean(id))
      ),
    ]
    ids.sort()
    return ids.join("\u0001")
  }, [voice.participants])

  useEffect(() => {
    const ids = participantIdSignature
      ? participantIdSignature.split("\u0001").filter(Boolean)
      : []
    if (ids.length === 0) {
      void Promise.resolve().then(() => {
        setVoiceAvatarByUserId({})
      })
      return
    }
    let cancelled = false
    void (async () => {
      const { data, error } = await supabase
        .from("profiles")
        .select("id, avatar_url")
        .in("id", ids)
      if (cancelled) return
      if (error) {
        console.warn("[live-voice] profile avatars", error.message)
        return
      }
      setVoiceAvatarByUserId((prev) => {
        const next = { ...prev }
        for (const row of data ?? []) {
          next[row.id] = row.avatar_url ?? null
        }
        return next
      })
    })()
    return () => {
      cancelled = true
    }
  }, [participantIdSignature])

  const stackPreview = useMemo(() => {
    const list = voice.participants
    const maxCircles = 5
    return {
      shown: list.slice(0, maxCircles),
      overflow: Math.max(0, list.length - maxCircles),
    }
  }, [voice.participants])

  if (!voice.session) return null

  const connecting =
    voice.connectionState === ConnectionState.Connecting ||
    voice.connectionState === ConnectionState.Reconnecting
  const muted = voice.session.canPublish && !voice.isMicrophoneEnabled
  const status = connectionStatusLabel(
    voice.connectionState,
    voice.session.canPublish,
    voice.isBusy
  )
  const participantCount = voice.participants.length

  const inFlow = placement === "embedded" || placement === "shell"
  const panelPositionClasses = inFlow
    ? "relative z-auto w-full pointer-events-auto"
    : "fixed right-[max(0.5rem,env(safe-area-inset-right))] z-[9990] pointer-events-auto max-md:bottom-[calc(var(--app-tab-bar-offset,0px)+0.5rem)] md:bottom-[max(0.75rem,env(safe-area-inset-bottom))]"

  const openVoiceRoom = () => {
    const roomId = voice.session?.roomId
    if (!roomId) return
    router.push(`/community?room=${encodeURIComponent(roomId)}`)
  }

  if (minimized && !inFlow) {
    return (
      <div
        className={panelPositionClasses}
        style={inFlow ? { maxWidth: "100%" } : undefined}
      >
        <button
          type="button"
          onClick={() => setMinimized(false)}
          className="flex items-center gap-2.5 rounded-full border border-emerald-500/35 bg-zinc-950 py-2 pl-3 pr-2.5 text-left text-zinc-50 shadow-lg transition hover:bg-zinc-900"
          aria-label="Expand General Voice panel"
        >
          <Headphones className="h-4 w-4 shrink-0 text-emerald-400" aria-hidden />
          <span className="max-w-[10rem] truncate text-sm font-medium text-emerald-100">
            {voice.session.roomLabel}
          </span>
          <span className="flex -space-x-2">
            {stackPreview.shown.map((p) => (
              <VoiceParticipantAvatar
                key={p.identity}
                participant={p}
                avatarUrl={voiceAvatarByUserId[p.identity]}
                sizeClass="h-7 w-7 text-[9px]"
              />
            ))}
            {stackPreview.overflow > 0 ? (
              <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-white/15 text-[10px] font-bold text-emerald-100 ring-2 ring-zinc-950">
                +{stackPreview.overflow}
              </div>
            ) : null}
          </span>
          <span className="rounded-full bg-white/10 px-2 py-0.5 text-[11px] font-semibold tabular-nums text-emerald-200/90">
            {participantCount}
          </span>
          <ChevronUp className="h-4 w-4 shrink-0 text-zinc-400" aria-hidden />
        </button>
      </div>
    )
  }

  return (
    <div
      className={panelPositionClasses}
      style={{
        maxWidth: inFlow ? "100%" : "min(calc(100vw - 1rem), 22rem)",
      }}
    >
      <div
        className="flex w-full flex-col rounded-xl border border-emerald-500/30 bg-zinc-950 text-zinc-50 shadow-xl"
        role="region"
        aria-label="General Voice"
      >
        {/* Member list expands above controls (grows upward in the bottom-anchored panel). */}
        {membersOpen ? (
          <div className="max-h-48 overflow-y-auto border-b border-white/10 px-3 py-2">
            <TradeRoomLiveModerationErrorNote
              className="mb-2"
              message={moderationError}
              onDismiss={() => setModerationError(null)}
            />
            <p className="mb-2 text-[10px] font-semibold uppercase tracking-wide text-zinc-500">
              In voice
            </p>
            <ul className="space-y-2">
              {voice.participants.map((p) => {
                const modMenu =
                  !p.isLocal &&
                  voice.session?.roomId &&
                  moderationCtx.accessToken &&
                  moderationCtx.roomId === voice.session.roomId &&
                  (moderationCtx.canModerateRoom || moderationCtx.canManageRoom) &&
                  moderationUiCanActOnMember(moderationCtx, p.identity) ? (
                    <TradeRoomLiveParticipantModerationMenu
                      surface="general-voice"
                      roomId={voice.session.roomId}
                      accessToken={moderationCtx.accessToken}
                      targetUserId={p.identity}
                      targetDisplayName={p.name}
                      liveVoiceKind={moderationCtx.liveVoiceKind}
                      isTargetMuted={p.isMuted}
                      onError={setModerationError}
                      onSuccess={() => setModerationError(null)}
                    />
                  ) : null
                return (
                  <li key={p.identity} className="flex items-center gap-2.5">
                    <VoiceParticipantAvatar
                      participant={p}
                      avatarUrl={voiceAvatarByUserId[p.identity]}
                      sizeClass="h-9 w-9 text-[11px]"
                    />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm text-zinc-100">
                        {p.name}
                        {p.isLocal ? (
                          <span className="text-zinc-500"> · You</span>
                        ) : null}
                      </p>
                      <p className="text-[11px] text-zinc-500">
                        {p.isMuted ? "Muted" : "In voice"}
                      </p>
                    </div>
                    {modMenu}
                    {p.isMuted ? (
                      <MicOff
                        className="h-3.5 w-3.5 shrink-0 text-zinc-500"
                        aria-hidden
                      />
                    ) : null}
                  </li>
                )
              })}
            </ul>
          </div>
        ) : null}

        <div className="flex items-start gap-2.5 border-b border-white/10 px-3.5 py-2.5">
          <Headphones
            className="mt-0.5 h-4 w-4 shrink-0 text-emerald-400"
            aria-hidden
          />
          <div className="min-w-0 flex-1">
            {inFlow ? (
              <button
                type="button"
                onClick={openVoiceRoom}
                className="truncate text-left text-sm font-semibold text-emerald-100"
              >
                {voice.session.roomLabel}
              </button>
            ) : (
              <p className="truncate text-sm font-semibold text-emerald-100">
                {voice.session.roomLabel}
              </p>
            )}
            <p className="mt-0.5 truncate text-xs leading-tight text-zinc-400">
              {status}
            </p>
            <p className="mt-0.5 text-xs text-zinc-500">
              {participantCount === 1
                ? "1 in voice"
                : `${participantCount} in voice`}
            </p>
          </div>
          {inFlow ? null : (
            <button
              type="button"
              onClick={() => setMinimized(true)}
              className="shrink-0 rounded-lg p-1 text-zinc-400 transition hover:bg-white/10 hover:text-zinc-200"
              aria-label="Minimize General Voice panel"
            >
              <ChevronDown className="h-4 w-4 text-zinc-300" aria-hidden />
            </button>
          )}
        </div>

        <button
          type="button"
          onClick={() => setMembersOpen((o) => !o)}
          className="flex w-full items-center justify-between gap-2 border-b border-white/10 px-3.5 py-2.5 text-left transition hover:bg-white/[0.04]"
          aria-expanded={membersOpen}
          aria-label={membersOpen ? "Hide who is in voice" : "Show who is in voice"}
        >
          <span className="flex min-w-0 items-center gap-2">
            <Users className="h-4 w-4 shrink-0 text-emerald-400/90" aria-hidden />
            <span className="text-xs font-medium text-zinc-200">Who&apos;s here</span>
          </span>
          <span className="flex items-center gap-2">
            <span className="flex -space-x-2">
              {stackPreview.shown.map((p) => (
                <VoiceParticipantAvatar
                  key={p.identity}
                  participant={p}
                  avatarUrl={voiceAvatarByUserId[p.identity]}
                  sizeClass="h-8 w-8 text-[10px]"
                />
              ))}
              {stackPreview.overflow > 0 ? (
                <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-white/12 text-[10px] font-bold text-emerald-100 ring-2 ring-zinc-950">
                  +{stackPreview.overflow}
                </div>
              ) : null}
            </span>
            {membersOpen ? (
              <ChevronUp className="h-4 w-4 shrink-0 text-zinc-500" aria-hidden />
            ) : (
              <ChevronDown className="h-4 w-4 shrink-0 text-zinc-500" aria-hidden />
            )}
          </span>
        </button>

        <div className="flex items-center justify-end gap-2 px-3 py-2.5">
          {voice.session.canPublish ? (
            <button
              type="button"
              aria-label={muted ? "Unmute microphone" : "Mute microphone"}
              disabled={voice.isBusy || connecting}
              onClick={() => void voice.setMuted(!muted)}
              className="rounded-lg bg-white/10 p-2.5 text-zinc-100 hover:bg-white/15 disabled:opacity-50"
            >
              {muted ? (
                <MicOff className="h-5 w-5 text-zinc-100" aria-hidden />
              ) : (
                <Mic className="h-5 w-5 text-zinc-100" aria-hidden />
              )}
            </button>
          ) : null}
          <button
            type="button"
            aria-label="Leave General Voice"
            disabled={voice.isBusy}
            onClick={() => void voice.leave()}
            className="rounded-lg bg-red-500/25 px-3 py-2 text-sm font-semibold text-red-100 hover:bg-red-500/40 disabled:opacity-50"
          >
            <span className="inline-flex items-center gap-1.5">
              <PhoneOff className="h-5 w-5" aria-hidden />
              Leave
            </span>
          </button>
        </div>

        {voice.error ? (
          <p className="border-t border-white/10 px-3.5 py-2 text-xs text-red-300">
            {voice.error}
          </p>
        ) : null}
        {voice.diagnostics && !voice.diagnostics.canPlaybackAudio ? (
          <div className="border-t border-white/10 px-3.5 py-2">
            <button
              type="button"
              className="w-full rounded-lg bg-amber-600/90 px-2 py-2 text-xs font-medium text-white hover:bg-amber-500"
              onClick={() => void voice.resumePlayback()}
            >
              Enable audio playback
            </button>
          </div>
        ) : null}
      </div>
    </div>
  )
}
