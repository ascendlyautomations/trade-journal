"use client"

import type { ShareConversationRow } from "@/lib/shareToConversations"
import type { ShareProfileRow } from "@/lib/shareRecipientSearch"

type ShareRecipientPickerProps = {
  conversations: ShareConversationRow[]
  loading: boolean
  searchQuery: string
  onSearchQueryChange: (value: string) => void
  filteredConversations: ShareConversationRow[]
  userResults: ShareProfileRow[]
  userSearchLoading: boolean
  selectedConversationIds: string[]
  selectedUserIds: string[]
  onToggleConversation: (id: string) => void
  onToggleUser: (user: ShareProfileRow) => void
}

function rowButtonClass(selected: boolean) {
  return `w-full flex items-center gap-3 p-2 rounded cursor-pointer text-left ${
    selected ? "bg-blue-500/20" : "hover:bg-white/10"
  }`
}

export default function ShareRecipientPicker({
  conversations,
  loading,
  searchQuery,
  onSearchQueryChange,
  filteredConversations,
  userResults,
  userSearchLoading,
  selectedConversationIds,
  selectedUserIds,
  onToggleConversation,
  onToggleUser,
}: ShareRecipientPickerProps) {
  const isSearching = searchQuery.trim().length > 0

  return (
    <div className="mb-3">
      <input
        type="search"
        placeholder="Search conversations or users..."
        value={searchQuery}
        onChange={(e) => onSearchQueryChange(e.target.value)}
        className="w-full p-2 bg-white/5 rounded mb-3 text-sm"
        autoComplete="off"
      />

      {loading ? (
        <p className="text-sm text-gray-400">Loading chats...</p>
      ) : isSearching ? (
        <div className="max-h-52 overflow-y-auto space-y-3">
          {filteredConversations.length > 0 ? (
            <div>
              <p className="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">
                Conversations
              </p>
              <div className="space-y-2">
                {filteredConversations.map((conv) => (
                  <button
                    key={conv.id}
                    type="button"
                    onClick={() => onToggleConversation(conv.id)}
                    className={rowButtonClass(
                      selectedConversationIds.includes(conv.id)
                    )}
                  >
                    <img
                      src={conv.avatar_url || "/default-avatar.png"}
                      className="w-8 h-8 rounded-full object-cover"
                      alt=""
                      loading="lazy"
                      decoding="async"
                    />
                    <span>
                      {conv.name || (conv.is_group ? "Group Chat" : "Chat")}
                    </span>
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          {userSearchLoading ? (
            <p className="text-sm text-gray-400">Searching users...</p>
          ) : userResults.length > 0 ? (
            <div>
              <p className="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">
                People
              </p>
              <div className="space-y-2">
                {userResults.map((profile) => (
                  <button
                    key={profile.id}
                    type="button"
                    onClick={() => onToggleUser(profile)}
                    className={rowButtonClass(
                      selectedUserIds.includes(profile.id)
                    )}
                  >
                    <img
                      src={profile.avatar_url || "/default-avatar.png"}
                      className="w-8 h-8 rounded-full object-cover"
                      alt=""
                      loading="lazy"
                      decoding="async"
                    />
                    <div className="flex flex-col text-left">
                      <span>{profile.name || profile.username}</span>
                      <span className="text-xs text-gray-400">
                        @{profile.username}
                      </span>
                    </div>
                  </button>
                ))}
              </div>
            </div>
          ) : null}

          {!userSearchLoading &&
          filteredConversations.length === 0 &&
          userResults.length === 0 ? (
            <p className="text-sm text-gray-400">No matches found.</p>
          ) : null}
        </div>
      ) : conversations.length === 0 ? (
        <p className="text-sm text-gray-400">
          No recent conversations. Search for someone to message.
        </p>
      ) : (
        <>
          <p className="mb-2 text-xs font-medium uppercase tracking-wide text-gray-400">
            Recent Conversations
          </p>
          <div className="max-h-52 overflow-y-auto space-y-2">
            {conversations.map((conv) => (
              <button
                key={conv.id}
                type="button"
                onClick={() => onToggleConversation(conv.id)}
                className={rowButtonClass(
                  selectedConversationIds.includes(conv.id)
                )}
              >
                <img
                  src={conv.avatar_url || "/default-avatar.png"}
                  className="w-8 h-8 rounded-full object-cover"
                  alt=""
                  loading="lazy"
                  decoding="async"
                />
                <span>
                  {conv.name || (conv.is_group ? "Group Chat" : "Chat")}
                </span>
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  )
}
