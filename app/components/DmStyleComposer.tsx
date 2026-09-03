"use client"

import {
  useEffect,
  useId,
  useLayoutEffect,
  useRef,
  useState,
  type ChangeEvent,
  type KeyboardEvent,
  type ReactNode,
  type RefObject,
} from "react"
import { useAutoResizeTextarea } from "@/lib/useAutoResizeTextarea"
import { applyTextareaNewlineInsert } from "@/lib/insertTextareaNewline"
import { useVoiceRecorder } from "@/lib/useVoiceRecorder"
import { formatVoiceDuration, type VoiceRecordingFormat } from "@/lib/voiceMessage"

export type VoiceSendPayload = {
  blob: Blob
  durationMs: number
  format: VoiceRecordingFormat
}

export type DmStyleComposerProps = {
  value: string
  onChange: (value: string) => void
  onSend: () => void
  placeholder?: string
  textDisabled?: boolean
  sendDisabled?: boolean
  onImageChange: (e: ChangeEvent<HTMLInputElement>) => void
  imageDisabled?: boolean
  onTradeClick?: () => void
  tradeDisabled?: boolean
  onSendVoice?: (payload: VoiceSendPayload) => void
  voiceDisabled?: boolean
  /** Shown above the input row (e.g. typing indicator) */
  beforeRow?: ReactNode
  /** Shown below the input row (e.g. “Seen”, file name) */
  afterRow?: ReactNode
  /** Optional ref on the hidden file input (Messages clears this after send) */
  fileInputRef?: RefObject<HTMLInputElement | null>
}

const desktopActionBtnClass =
  "flex shrink-0 items-center justify-center rounded bg-[#1f2937] p-2 md:hover:bg-[#334155] disabled:cursor-not-allowed disabled:opacity-50"

const messageFieldClass =
  "min-w-0 flex-1 resize-none rounded bg-[#111827] px-3 py-2 text-sm leading-normal text-white placeholder:text-gray-400 disabled:opacity-60"

const MAX_TEXTAREA_LINES = 3

const hasShareActions = (
  imageDisabled: boolean,
  onTradeClick?: () => void
) => !imageDisabled || Boolean(onTradeClick)

function SharePlusIcon({ className }: { className?: string }) {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth={2}
      strokeLinecap="round"
      strokeLinejoin="round"
      className={className}
      aria-hidden
    >
      <circle cx="12" cy="12" r="10" />
      <path d="M12 8v8M8 12h8" />
    </svg>
  )
}

/**
 * Shared bottom composer matching the Messages / DM layout.
 */
export default function DmStyleComposer({
  value,
  onChange,
  onSend,
  placeholder = "Send message...",
  textDisabled = false,
  sendDisabled = false,
  onImageChange,
  imageDisabled = false,
  onTradeClick,
  tradeDisabled = false,
  onSendVoice,
  voiceDisabled = false,
  beforeRow,
  afterRow,
  fileInputRef,
}: DmStyleComposerProps) {
  const [mobileAttachOpen, setMobileAttachOpen] = useState(false)
  const fileInputId = useId()
  const textareaRef = useAutoResizeTextarea(value, {
    maxLines: MAX_TEXTAREA_LINES,
  })
  const internalFileInputRef = useRef<HTMLInputElement>(null)
  const resolvedFileInputRef = fileInputRef ?? internalFileInputRef
  const pendingCaretRef = useRef<number | null>(null)
  const showShare = hasShareActions(imageDisabled, onTradeClick)
  const voiceRecorder = useVoiceRecorder()
  const canSendText = value.trim().length > 0
  const voiceEnabled = Boolean(onSendVoice) && !voiceDisabled
  const showMic =
    voiceEnabled && !canSendText && voiceRecorder.phase !== "recording"

  useLayoutEffect(() => {
    const el = textareaRef.current
    const caret = pendingCaretRef.current
    if (!el || caret == null) return
    pendingCaretRef.current = null
    el.setSelectionRange(caret, caret)
  }, [value, textareaRef])

  useEffect(() => {
    if (!voiceRecorder.completedTake || !onSendVoice) return
    onSendVoice(voiceRecorder.completedTake)
    voiceRecorder.consumeCompletedTake()
  }, [
    voiceRecorder.completedTake,
    onSendVoice,
    voiceRecorder.consumeCompletedTake,
  ])

  function handleTextareaKeyDown(e: KeyboardEvent<HTMLTextAreaElement>) {
    if (e.key !== "Enter") return

    if (e.ctrlKey || e.metaKey) {
      e.preventDefault()
      pendingCaretRef.current = applyTextareaNewlineInsert(
        e.currentTarget,
        value,
        onChange
      )
      return
    }

    e.preventDefault()
    if (!sendDisabled && canSendText) onSend()
  }

  function openPhotoPicker() {
    setMobileAttachOpen(false)
    if (imageDisabled) return
    resolvedFileInputRef.current?.click()
  }

  function openTradePicker() {
    setMobileAttachOpen(false)
    if (tradeDisabled || !onTradeClick) return
    onTradeClick()
  }

  async function handleVoiceSend() {
    await voiceRecorder.finish()
  }

  return (
    <div className="relative mt-auto shrink-0 border-t border-white/10 bg-[#0B1220] p-2 md:bg-[#020617] md:p-4">
      {beforeRow ? <div className="mb-1">{beforeRow}</div> : null}
      <input
        ref={resolvedFileInputRef}
        id={fileInputId}
        type="file"
        accept="image/*"
        className="hidden"
        disabled={imageDisabled}
        onChange={onImageChange}
      />
      {voiceRecorder.phase === "recording" ? (
        <div className="flex w-full items-center gap-3">
          <div className="flex min-w-0 flex-1 items-center gap-2">
            <span className="inline-block h-2 w-2 shrink-0 rounded-full bg-red-500" />
            <span className="font-mono text-sm text-white">
              {formatVoiceDuration(voiceRecorder.elapsedMs / 1000)}
            </span>
          </div>
          <button
            type="button"
            aria-label="Cancel recording"
            onClick={voiceRecorder.cancel}
            className="shrink-0 rounded px-3 py-2 text-sm text-gray-300 hover:bg-white/10 hover:text-white"
          >
            Cancel
          </button>
          <button
            type="button"
            aria-label="Send voice message"
            onClick={() => void handleVoiceSend()}
            className="shrink-0 rounded bg-blue-500 px-3 py-2 text-sm font-medium text-white hover:bg-blue-600"
          >
            Send
          </button>
        </div>
      ) : (
        <div className="flex w-full items-end gap-1.5">
          <textarea
            ref={textareaRef}
            rows={1}
            placeholder={placeholder}
            value={value}
            disabled={textDisabled}
            onChange={(e) => onChange(e.target.value)}
            onKeyDown={handleTextareaKeyDown}
            className={messageFieldClass}
          />
          {showShare ? (
            <button
              type="button"
              aria-label="Share photo or trade"
              title="Share photo or trade"
              onClick={() => setMobileAttachOpen(true)}
              className="flex h-10 w-10 min-h-[40px] min-w-[40px] shrink-0 items-center justify-center rounded-full bg-blue-500 text-white shadow-md transition active:scale-95 md:hidden hover:bg-blue-600"
            >
              <SharePlusIcon className="h-5 w-5" />
            </button>
          ) : null}
          <label
            htmlFor={fileInputId}
            className={`${desktopActionBtnClass} hidden cursor-pointer md:flex`}
          >
            <span aria-hidden>📷</span>
          </label>
          {onTradeClick ? (
            <button
              type="button"
              onClick={onTradeClick}
              disabled={tradeDisabled}
              aria-label="Send a trade"
              title="Send a trade"
              className={`${desktopActionBtnClass} hidden md:flex`}
            >
              <span aria-hidden>📊</span>
            </button>
          ) : null}
          {showMic ? (
            <button
              type="button"
              aria-label="Record voice message"
              title="Record voice message"
              disabled={voiceDisabled}
              onClick={() => void voiceRecorder.start()}
              className={`${desktopActionBtnClass} flex`}
            >
              <span aria-hidden>🎤</span>
            </button>
          ) : null}
          {canSendText ? (
            <button
              type="button"
              onClick={onSend}
              disabled={sendDisabled}
              className="shrink-0 whitespace-nowrap rounded bg-blue-500 px-3 py-2 text-sm hover:bg-blue-600 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Send
            </button>
          ) : null}
        </div>
      )}
      {voiceRecorder.lastError ? (
        <p className="mt-2 text-xs text-red-400">{voiceRecorder.lastError}</p>
      ) : null}
      {afterRow ? <div className="mt-2">{afterRow}</div> : null}

      {mobileAttachOpen ? (
        <div
          className="fixed inset-0 z-[70] md:hidden"
          role="presentation"
          onClick={() => setMobileAttachOpen(false)}
        >
          <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" />
          <div
            className="absolute bottom-0 left-0 right-0 rounded-t-2xl border-t border-white/10 bg-[#0f172a] p-4 pb-[max(1rem,var(--safe-area-bottom))] shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mx-auto mb-3 h-1 w-10 rounded-full bg-white/20" />
            <div className="space-y-1">
              <button
                type="button"
                disabled={imageDisabled}
                onClick={openPhotoPicker}
                className="flex w-full items-center gap-3 rounded-lg px-3 py-3 text-left text-sm text-white hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50"
              >
                <span aria-hidden>📷</span>
                <span>Send Photo</span>
              </button>
              {onTradeClick ? (
                <button
                  type="button"
                  disabled={tradeDisabled}
                  onClick={openTradePicker}
                  className="flex w-full items-center gap-3 rounded-lg px-3 py-3 text-left text-sm text-white hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <span aria-hidden>📊</span>
                  <span>Send Trade</span>
                </button>
              ) : null}
              {voiceEnabled ? (
                <button
                  type="button"
                  disabled={voiceDisabled}
                  onClick={() => {
                    void voiceRecorder.start().then((started) => {
                      if (started) setMobileAttachOpen(false)
                    })
                  }}
                  className="flex w-full items-center gap-3 rounded-lg px-3 py-3 text-left text-sm text-white hover:bg-white/10 disabled:cursor-not-allowed disabled:opacity-50"
                >
                  <span aria-hidden>🎤</span>
                  <span>Voice Message</span>
                </button>
              ) : null}
            </div>
            <button
              type="button"
              onClick={() => setMobileAttachOpen(false)}
              className="mt-3 w-full rounded-lg py-2.5 text-sm text-gray-400 hover:text-white"
            >
              Cancel
            </button>
          </div>
        </div>
      ) : null}
    </div>
  )
}
