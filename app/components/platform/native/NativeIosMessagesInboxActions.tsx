"use client"

import Link from "next/link"
import { NATIVE_IOS_PAGE_HEADER_ACTION_CLASS } from "@/app/components/platform/PlatformPageHeader"
import { hapticLight } from "@/lib/nativeHaptics"

type NativeIosMessagesInboxActionsProps = {
  onPersonalChat: () => void
  onGroupChat: () => void
}

/**
 * Native Messages inbox top row — New Chat · Trade Rooms on the left,
 * Settings (gear) utility on the far right → `/settings#notifications`.
 * New Chat opens a Capacitor action sheet (Personal / Group / Cancel).
 */
export default function NativeIosMessagesInboxActions({
  onPersonalChat,
  onGroupChat,
}: NativeIosMessagesInboxActionsProps) {
  async function handleNewChat() {
    hapticLight("new-chat")
    try {
      const { ActionSheet, ActionSheetButtonStyle } = await import(
        "@capacitor/action-sheet"
      )
      const result = await ActionSheet.showActions({
        options: [
          { title: "Personal Chat" },
          { title: "Group Chat" },
          { title: "Cancel", style: ActionSheetButtonStyle.Cancel },
        ],
      })
      if (result.index === 0) onPersonalChat()
      else if (result.index === 1) onGroupChat()
    } catch {
      // Dismissed / unavailable — no-op.
    }
  }

  return (
    <div
      data-tt-messages-inbox-actions
      className="mb-3 flex shrink-0 items-center gap-2"
    >
      <div className="flex min-w-0 flex-wrap items-center gap-2">
        <button
          type="button"
          onClick={() => {
            void handleNewChat()
          }}
          className="inline-flex min-h-10 items-center rounded-lg bg-blue-500 px-3 py-1.5 text-sm font-medium text-white active:bg-blue-600"
        >
          New Chat
        </button>
        <Link
          href="/community"
          onClick={() => hapticLight("trade-rooms")}
          className="inline-flex min-h-10 items-center gap-1.5 rounded-lg border border-blue-400/30 bg-blue-500/15 px-3 py-1.5 text-sm font-medium text-blue-200 active:bg-blue-500/25"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            strokeWidth="1.75"
            strokeLinecap="round"
            strokeLinejoin="round"
            className="h-4 w-4 shrink-0"
            aria-hidden
          >
            <path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2" />
            <circle cx="9" cy="7" r="4" />
            <path d="M22 21v-2a4 4 0 0 0-3-3.87" />
            <path d="M16 3.13a4 4 0 0 1 0 7.75" />
          </svg>
          Trade Rooms
        </Link>
      </div>

      <Link
        href="/settings#notifications"
        aria-label="Messages notification settings"
        className={`ml-auto ${NATIVE_IOS_PAGE_HEADER_ACTION_CLASS}`}
        onClick={() => hapticLight("settings")}
      >
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="18"
          height="18"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden
        >
          <path d="M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z" />
          <circle cx="12" cy="12" r="3" />
        </svg>
      </Link>
    </div>
  )
}
