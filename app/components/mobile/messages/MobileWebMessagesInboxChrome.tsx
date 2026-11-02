"use client"

type MobileWebMessagesInboxChromeProps = {
  search: string
  onSearchChange: (value: string) => void
  onCompose: () => void
}

export default function MobileWebMessagesInboxChrome({
  search,
  onSearchChange,
}: MobileWebMessagesInboxChromeProps) {
  return (
    <div className="shrink-0 px-3 pb-2 pt-1">
      <label className="block">
        <span className="sr-only">Search messages</span>
        <input
          type="search"
          enterKeyHint="search"
          autoCapitalize="none"
          autoCorrect="off"
          spellCheck={false}
          value={search}
          onChange={(event) => onSearchChange(event.target.value)}
          placeholder="Search messages"
          className="h-11 w-full rounded-[14px] border border-white/10 bg-white/10 px-3 text-[15px] text-[color:var(--tt-text,#f0f3f6)] placeholder:text-[color:var(--tt-text-muted,#57606a)] focus:outline-none focus:ring-2 focus:ring-[#4EC4E0]/40"
        />
      </label>
    </div>
  )
}
