"use client"

import { useCallback, useEffect, useMemo, useState } from "react"
import { supabase } from "@/lib/supabaseClient"
import type { NotificationPreferenceKey } from "@/lib/notificationPreferences"
import {
  ensureNotificationPreferencesLoaded,
  getCachedNotificationPreferences,
  subscribeNotificationPreferencesCache,
  updateNotificationPreference,
} from "@/lib/notificationPreferencesCache"

type ToggleItem = {
  key: NotificationPreferenceKey
  label: string
  description?: string
}

type ToggleSection = {
  title: string
  items: ToggleItem[]
}

const PREFERENCE_SECTIONS: ToggleSection[] = [
  {
    title: "Social Notifications",
    items: [
      {
        key: "likes_enabled",
        label: "Likes",
        description:
          "Notify me when someone likes my trades, posts, or achievements.",
      },
      {
        key: "comments_enabled",
        label: "Comments",
        description:
          "Notify me when someone comments on my trades, posts, or achievements.",
      },
      {
        key: "replies_enabled",
        label: "Replies",
        description: "Notify me when someone replies to my comment.",
      },
      {
        key: "mentions_enabled",
        label: "Mentions",
        description: "Notify me when someone mentions me using @username.",
      },
      {
        key: "reactions_enabled",
        label: "Reactions",
        description: "Notify me when someone reacts to my content.",
      },
    ],
  },
  {
    title: "Followers",
    items: [
      {
        key: "followers_enabled",
        label: "New Followers",
        description: "Notify me when someone follows me.",
      },
      {
        key: "follow_requests_enabled",
        label: "Follow Requests",
        description: "Notify me about private profile follow requests.",
      },
      {
        key: "follow_request_accepts_enabled",
        label: "Accepted Follow Requests",
        description: "Notify me when someone accepts my follow request.",
      },
    ],
  },
  {
    title: "Messages",
    items: [
      {
        key: "direct_messages_enabled",
        label: "Direct Messages",
        description: "Notify me when someone sends a DM.",
      },
      {
        key: "story_replies_enabled",
        label: "Story Replies",
        description: "Notify me when someone replies to one of my stories.",
      },
      {
        key: "shares_enabled",
        label: "Shared Trades / Posts",
        description: "Notify me when someone shares content with me.",
      },
    ],
  },
  {
    title: "Trade Rooms",
    items: [
      {
        key: "room_messages_enabled",
        label: "Room Messages",
        description: "Notify me about new messages in Trade Rooms.",
      },
      {
        key: "room_mentions_enabled",
        label: "Room Mentions",
        description: "Notify me when I'm mentioned in a Trade Room.",
      },
      {
        key: "room_joins_enabled",
        label: "Room Joins",
        description: "Notify room owners when someone joins their room.",
      },
    ],
  },
  {
    title: "Achievements",
    items: [
      {
        key: "achievement_likes_enabled",
        label: "Achievement Likes",
        description: "Notify me when someone likes my achievement posts.",
      },
      {
        key: "achievement_comments_enabled",
        label: "Achievement Comments",
        description: "Notify me when someone comments on my achievements.",
      },
      {
        key: "achievement_unlocks_enabled",
        label: "New Achievements",
        description: "Notify me when I unlock a new achievement.",
      },
    ],
  },
  {
    title: "System",
    items: [
      {
        key: "product_updates_enabled",
        label: "Product Updates",
      },
      {
        key: "maintenance_enabled",
        label: "Maintenance Notifications",
      },
      {
        key: "announcements_enabled",
        label: "Feature Announcements",
      },
    ],
  },
]

function SettingsToggle({
  label,
  description,
  checked,
  disabled,
  onChange,
}: {
  label: string
  description?: string
  checked: boolean
  disabled?: boolean
  onChange: (next: boolean) => void
}) {
  return (
    <div
      className={`flex items-start justify-between gap-4 border-b border-white/5 py-3 last:border-b-0 ${
        disabled ? "opacity-45" : ""
      }`}
    >
      <div className="min-w-0">
        <p className="text-sm font-medium text-white">{label}</p>
        {description ? (
          <p className="mt-0.5 text-xs leading-relaxed text-gray-400">
            {description}
          </p>
        ) : null}
      </div>
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        aria-label={label}
        disabled={disabled}
        onClick={() => onChange(!checked)}
        className={`relative mt-0.5 h-6 w-11 shrink-0 rounded-full transition-colors disabled:cursor-not-allowed ${
          checked ? "bg-blue-500" : "bg-white/20"
        }`}
      >
        <span
          className={`absolute top-0.5 left-0.5 h-5 w-5 rounded-full bg-white shadow transition-transform ${
            checked ? "translate-x-5" : "translate-x-0"
          }`}
        />
      </button>
    </div>
  )
}

type Props = {
  userId: string | undefined
}

export default function NotificationPreferencesSettingsSection({
  userId,
}: Props) {
  const initialCached = useMemo(
    () => (userId ? getCachedNotificationPreferences(userId) : null),
    [userId]
  )
  const [preferences, setPreferences] = useState(initialCached)
  const [loading, setLoading] = useState(Boolean(userId) && !initialCached)
  const [savingKey, setSavingKey] = useState<NotificationPreferenceKey | null>(
    null
  )

  const refreshFromCache = useCallback(() => {
    if (!userId) return
    const cached = getCachedNotificationPreferences(userId)
    if (cached) setPreferences(cached)
  }, [userId])

  useEffect(() => {
    if (!userId) return
    return subscribeNotificationPreferencesCache(refreshFromCache)
  }, [userId, refreshFromCache])

  useEffect(() => {
    if (!userId) return
    let cancelled = false

    void (async () => {
      const cached = getCachedNotificationPreferences(userId)
      if (cached) {
        setPreferences(cached)
        setLoading(false)
        return
      }

      setLoading(true)
      const loaded = await ensureNotificationPreferencesLoaded(supabase, userId)
      if (!cancelled) {
        setPreferences(loaded)
        setLoading(false)
      }
    })()

    return () => {
      cancelled = true
    }
  }, [userId])

  async function handleToggle(
    key: NotificationPreferenceKey,
    next: boolean
  ) {
    if (!userId || !preferences || savingKey) return

    const previous = preferences
    const optimistic = { ...preferences, [key]: next }
    setPreferences(optimistic)
    setSavingKey(key)

    const saved = await updateNotificationPreference(supabase, userId, {
      [key]: next,
    })

    setSavingKey(null)
    if (saved) {
      setPreferences(saved)
    } else {
      setPreferences(previous)
    }
  }

  const masterEnabled = preferences?.notifications_enabled ?? true
  const controlsDisabled = !masterEnabled || Boolean(savingKey)

  if (!userId) return null

  if (loading && !preferences) {
    return (
      <div className="rounded-2xl border border-white/10 bg-white/5 p-6 text-sm text-gray-400 backdrop-blur-sm">
        Loading notification preferences…
      </div>
    )
  }

  if (!preferences) return null

  return (
    <div className="space-y-6">
      <section className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm">
        <SettingsToggle
          label="Enable Notifications"
          description="Turn off to stop all new notifications. Existing notifications stay in your inbox."
          checked={masterEnabled}
          disabled={savingKey === "notifications_enabled"}
          onChange={(next) => void handleToggle("notifications_enabled", next)}
        />
      </section>

      {PREFERENCE_SECTIONS.map((section) => (
        <section
          key={section.title}
          className="rounded-2xl border border-white/10 bg-white/5 p-6 backdrop-blur-sm"
        >
          <h3 className="mb-1 text-sm font-semibold uppercase tracking-wide text-blue-300">
            {section.title}
          </h3>
          <div className="mt-2">
            {section.items.map((item) => (
              <SettingsToggle
                key={item.key}
                label={item.label}
                description={item.description}
                checked={Boolean(preferences[item.key])}
                disabled={controlsDisabled || savingKey === item.key}
                onChange={(next) => void handleToggle(item.key, next)}
              />
            ))}
          </div>
        </section>
      ))}
    </div>
  )
}
