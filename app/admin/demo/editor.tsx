"use client"

import { useState } from "react"
import { DemoMediaField } from "@/app/admin/demo/media-field"
import {
  ACTIVITY_KINDS,
  STRESS_LABELS,
  TRADE_EMOTIONS,
  fromDateTimeLocal,
  mediaURL,
  moneyAmount,
  readPath,
  setMedia,
  setMoney,
  setPostMedia,
  sharedContent,
  sharedContentId,
  text,
  toDateTimeLocal,
  writePath,
  type DemoRecord,
} from "@/lib/demo/demoAdminModel"

export type DemoOption = { id: string; label: string }

export type DemoLookups = {
  profiles: DemoOption[]
  accounts: DemoOption[]
  trades: DemoOption[]
  posts: DemoOption[]
  clips: DemoOption[]
  achievements: DemoOption[]
  conversations: DemoOption[]
  rooms: DemoOption[]
  channels: DemoOption[]
  folders: DemoOption[]
}

const inputClass =
  "mt-1 w-full rounded-lg border border-white/15 bg-black/30 px-3 py-2 text-sm text-white outline-none focus:border-emerald-400/60"

export function DemoEditor({
  entity,
  record,
  role,
  lookups,
  onChange,
  onRole,
}: {
  entity: string
  record: DemoRecord
  role?: string
  lookups: DemoLookups
  onChange: (record: DemoRecord) => void
  onRole?: (role: string) => void
}) {
  const set = (path: string, value: unknown) => onChange(writePath(record, path, value))
  const str = (path: string) => text(readPath(record, path))

  return (
    <div className="space-y-3">
      {entity === "profile" ? (
        <>
          <Field label="Display name" value={str("displayName")} onChange={(value) => set("displayName", value)} />
          <Field label="Username" value={str("username")} onChange={(value) => set("username", value)} />
          <DemoMediaField
            label="Avatar"
            url={mediaURL(record.avatar)}
            entityType="profile"
            entityId={str("id")}
            kind="image"
            onChange={(url) => onChange(setMedia(record, "avatar", url))}
          />
          <Area label="Bio" value={str("bio")} onChange={(value) => set("bio", value)} />
          <Select
            label="Trader type"
            value={str("traderType")}
            allowEmpty
            options={[
              { id: "Futures", label: "Futures" },
              { id: "Options", label: "Options" },
              { id: "Investor", label: "Investor" },
              { id: "Forex", label: "Forex" },
            ]}
            onChange={(value) => set("traderType", value || null)}
          />
          <Field label="Trading style" value={str("tradingStyle")} onChange={(value) => set("tradingStyle", value)} />
          <Field label="Primary market" value={str("primaryMarket")} onChange={(value) => set("primaryMarket", value)} />
          <Check label="Private profile" checked={record.isPrivate === true} onChange={(value) => set("isPrivate", value)} />
          {role && role !== "viewer" && onRole ? (
            <Select
              label="Role"
              value={role}
              options={[
                { id: "peer", label: "Social profile" },
                { id: "host", label: "Trade Room host" },
              ]}
              onChange={onRole}
            />
          ) : (
            <p className="text-xs text-gray-400">This is the primary Demo user. The app requires this profile.</p>
          )}
        </>
      ) : null}

      {entity === "account" ? (
        <>
          <Field label="Account name" value={str("name")} onChange={(value) => set("name", value)} />
          <Field label="Account number" value={str("accountNumber")} onChange={(value) => set("accountNumber", value || null)} />
          <Select
            label="Mode"
            value={str("mode") || "evaluation"}
            options={[
              { id: "evaluation", label: "Evaluation" },
              { id: "funded", label: "Funded" },
              { id: "live", label: "Live" },
              { id: "sim", label: "Sim" },
              { id: "backtest", label: "Backtest" },
            ]}
            onChange={(value) => set("mode", value)}
          />
          <Select
            label="Firm / broker type"
            value={str("category") || "propFirm"}
            options={[
              { id: "propFirm", label: "Prop firm" },
              { id: "broker", label: "Broker" },
              { id: "personal", label: "Personal" },
              { id: "backtest", label: "Backtest" },
            ]}
            onChange={(value) => set("category", value)}
          />
          <Field
            label="Starting balance"
            value={moneyAmount(record, "size")?.toString() ?? ""}
            onChange={(value) => onChange(setMoney(record, "size", value))}
          />
          <Check
            label="Show in account lists"
            checked={record.showInAccountDropdowns !== false}
            onChange={(value) => set("showInAccountDropdowns", value)}
          />
          <Check label="Active" checked={record.isActive !== false} onChange={(value) => set("isActive", value)} />
        </>
      ) : null}

      {entity === "trade" ? (
        <>
          <SearchSelect label="Account" value={str("accountID")} options={lookups.accounts} onChange={(value) => set("accountID", value)} />
          <Field label="Symbol" value={str("symbol.ticker")} onChange={(value) => set("symbol.ticker", value.toUpperCase())} />
          <Select
            label="Side"
            value={str("side") || "long"}
            options={[
              { id: "long", label: "Long" },
              { id: "short", label: "Short" },
            ]}
            onChange={(value) => set("side", value)}
          />
          <Field label="Quantity" value={str("quantity")} onChange={(value) => set("quantity", Number(value) || 0)} />
          <Field label="Entry price" value={str("entryPrice")} onChange={(value) => set("entryPrice", value === "" ? null : Number(value))} />
          <Field label="Exit price" value={str("exitPrice")} onChange={(value) => set("exitPrice", value === "" ? null : Number(value))} />
          <Field
            label="P&L"
            value={moneyAmount(record)?.toString() ?? ""}
            onChange={(value) => onChange(setMoney(record, "realizedPnL", value))}
          />
          <Field label="Entry" type="datetime-local" value={toDateTimeLocal(record.entryAt)} onChange={(value) => set("entryAt", fromDateTimeLocal(value))} />
          <Field label="Exit" type="datetime-local" value={toDateTimeLocal(record.exitAt)} onChange={(value) => set("exitAt", fromDateTimeLocal(value))} />
          <Area label="Notes" value={str("notes") || str("notePreview")} onChange={(value) => onChange(writePath(writePath(record, "notes", value || null), "notePreview", value || null))} />
          <DemoMediaField
            label="Screenshot"
            url={mediaURL(record.thumbnail)}
            entityType="trade"
            entityId={str("id")}
            kind="image"
            onChange={(url) => onChange(setMedia(record, "thumbnail", url))}
          />
          <Field label="Confidence (1–5)" value={str("confidence")} onChange={(value) => set("confidence", value === "" ? null : Number(value))} />
          <Select label="Emotion" value={str("emotion")} options={emotionOptions} allowEmpty onChange={(value) => set("emotion", value || null)} />
          <Select label="Exit emotion" value={str("exitEmotion")} options={emotionOptions} allowEmpty onChange={(value) => set("exitEmotion", value || null)} />
          <Select
            label="Followed plan"
            value={record.followedPlan == null ? "" : record.followedPlan ? "yes" : "no"}
            allowEmpty
            options={[
              { id: "yes", label: "Yes" },
              { id: "no", label: "No" },
            ]}
            onChange={(value) => set("followedPlan", value === "" ? null : value === "yes")}
          />
          <Field label="Execution rating (1–5)" value={str("executionRating")} onChange={(value) => set("executionRating", value === "" ? null : Number(value))} />
          <Area label="Psychology notes" value={str("psychologyNotes")} onChange={(value) => set("psychologyNotes", value || null)} />
          <Select
            label="Visibility"
            value={str("visibility") || "public"}
            options={[
              { id: "public", label: "Public" },
              { id: "followersOnly", label: "Followers" },
              { id: "private", label: "Private" },
            ]}
            onChange={(value) => set("visibility", value)}
          />
          <Field label="Public caption" value={str("publicCaption")} onChange={(value) => set("publicCaption", value || null)} />
          <Field label="Strategy" value={str("strategy")} onChange={(value) => set("strategy", value || null)} />
          <Field label="Session" value={str("sessionLabel")} onChange={(value) => set("sessionLabel", value || null)} />
        </>
      ) : null}

      {entity === "post" || entity === "clip" || entity === "story" ? (
        <>
          <SearchSelect label="Author" value={str("authorProfileID")} options={lookups.profiles} onChange={(value) => set("authorProfileID", value)} />
          {entity !== "story" ? (
            <SearchSelect
              label="Trade"
              value={str("linkedTradeID")}
              options={lookups.trades}
              allowEmpty
              emptyLabel="No trade"
              onChange={(value) => set("linkedTradeID", value || null)}
            />
          ) : null}
          {entity === "post" ? (
            <>
              <Area label="Caption" value={str("body")} onChange={(value) => set("body", value)} />
              <DemoMediaField
                label="Image"
                url={mediaURL(record.media)}
                entityType="post"
                entityId={str("id")}
                kind="image"
                onChange={(url) => onChange(setPostMedia(record, url))}
              />
            </>
          ) : null}
          {entity === "clip" ? (
            <>
              <Field label="Caption" value={str("caption")} onChange={(value) => set("caption", value)} />
              <DemoMediaField
                label="Video"
                url={mediaURL(record.video)}
                entityType="clip"
                entityId={str("id")}
                kind="video"
                onChange={(url) => onChange(setMedia(record, "video", url, "video"))}
              />
              <DemoMediaField
                label="Thumbnail"
                url={mediaURL(record.thumbnail)}
                entityType="clip"
                entityId={str("id")}
                kind="image"
                onChange={(url) => onChange(setMedia(record, "thumbnail", url))}
              />
            </>
          ) : null}
          {entity === "story" ? (
            <DemoMediaField
              label="Story media"
              url={mediaURL(record.media)}
              entityType="story"
              entityId={str("id")}
              kind="either"
              onChange={(url, mediaKind) => onChange(setMedia(record, "media", url, mediaKind))}
            />
          ) : null}
          <Field label="Created" type="datetime-local" value={toDateTimeLocal(record.createdAt)} onChange={(value) => set("createdAt", fromDateTimeLocal(value))} />
          {entity !== "story" ? (
            <Select
              label="Visibility"
              value={str("visibility") || "public"}
              options={[
                { id: "public", label: "Public" },
                { id: "followersOnly", label: "Followers" },
                { id: "private", label: "Private" },
              ]}
              onChange={(value) => set("visibility", value)}
            />
          ) : null}
        </>
      ) : null}

      {entity === "achievement" ? (
        <>
          <Field label="Title" value={str("title")} onChange={(value) => set("title", value)} />
          <SearchSelect label="Owner" value={str("ownerProfileID")} options={lookups.profiles} onChange={(value) => set("ownerProfileID", value)} />
          <SearchSelect label="Account" value={str("accountID")} options={lookups.accounts} allowEmpty emptyLabel="No account" onChange={(value) => set("accountID", value || null)} />
          <Area label="Description" value={str("description")} onChange={(value) => set("description", value)} />
          <Field label="Firm" value={str("firm")} onChange={(value) => set("firm", value)} />
          <DemoMediaField
            label="Image"
            url={mediaURL(record.image)}
            entityType="achievement"
            entityId={str("id")}
            kind="image"
            onChange={(url) => onChange(setMedia(record, "image", url))}
          />
          <Field
            label="Value"
            value={moneyAmount(record, "value")?.toString() ?? ""}
            onChange={(value) => onChange(setMoney(record, "value", value))}
          />
          <Field label="Achieved" type="datetime-local" value={toDateTimeLocal(record.achievedAt)} onChange={(value) => set("achievedAt", fromDateTimeLocal(value))} />
          <Check label="Public" checked={record.isPublic !== false} onChange={(value) => set("isPublic", value)} />
          <Check label="Featured" checked={record.isFeatured === true} onChange={(value) => set("isFeatured", value)} />
        </>
      ) : null}

      {entity === "activity" ? (
        <ActivityFields record={record} lookups={lookups} onChange={onChange} />
      ) : null}

      {entity === "conversation" ? (
        <>
          <Field label="Title" value={str("title")} onChange={(value) => set("title", value)} />
          <p className="text-xs text-gray-400">Participants</p>
          <div className="max-h-40 space-y-1 overflow-auto rounded-lg border border-white/10 p-2">
            {lookups.profiles.map((profile) => {
              const selected = Array.isArray(record.participantProfileIDs)
                ? (record.participantProfileIDs as unknown[]).map(String).includes(profile.id)
                : false
              return (
                <label key={profile.id} className="flex items-center gap-2 text-sm">
                  <input
                    type="checkbox"
                    checked={selected}
                    onChange={(event) => {
                      const current = Array.isArray(record.participantProfileIDs)
                        ? (record.participantProfileIDs as unknown[]).map(String)
                        : []
                      const next = event.target.checked
                        ? [...current, profile.id]
                        : current.filter((id) => id !== profile.id)
                      onChange(writePath(record, "participantProfileIDs", next))
                    }}
                  />
                  {profile.label}
                </label>
              )
            })}
          </div>
        </>
      ) : null}

      {entity === "message" || entity === "room_message" ? (
        <>
          <SearchSelect
            label="Sender"
            value={str("senderProfileID")}
            options={lookups.profiles}
            onChange={(value) => set("senderProfileID", value)}
          />
          {entity === "room_message" ? (
            <SearchSelect label="Channel" value={str("channelID")} options={lookups.channels} allowEmpty emptyLabel="No channel" onChange={(value) => set("channelID", value || null)} />
          ) : null}
          <Area label="Message" value={str("body")} onChange={(value) => set("body", value)} />
          <Field label="Time" type="datetime-local" value={toDateTimeLocal(record.createdAt)} onChange={(value) => set("createdAt", fromDateTimeLocal(value))} />
          <SharedPicker record={record} lookups={lookups} onChange={onChange} room={entity === "room_message"} />
        </>
      ) : null}

      {entity === "room" ? (
        <>
          <Field
            label="Room name"
            value={str("name")}
            onChange={(value) => {
              const slug = value.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "")
              onChange(writePath(writePath(record, "name", value), "slug", slug || "room"))
            }}
          />
          <Field label="Slug" value={str("slug")} onChange={(value) => set("slug", value)} />
          <Area label="Description" value={str("description")} onChange={(value) => set("description", value)} />
          <DemoMediaField
            label="Image"
            url={mediaURL(record.image)}
            entityType="room"
            entityId={str("id")}
            kind="image"
            onChange={(url) => onChange(setMedia(record, "image", url))}
          />
          <SearchSelect label="Owner" value={str("ownerProfileID")} options={lookups.profiles} onChange={(value) => set("ownerProfileID", value)} />
          <Area label="Rules" value={str("rules")} onChange={(value) => set("rules", value)} />
        </>
      ) : null}

      {entity === "membership" ? (
        <>
          <SearchSelect label="Profile" value={str("profileID")} options={lookups.profiles} onChange={(value) => set("profileID", value)} />
          <Select
            label="Role"
            value={str("role") || "member"}
            options={[
              { id: "owner", label: "Owner" },
              { id: "admin", label: "Admin" },
              { id: "member", label: "Member" },
            ]}
            onChange={(value) => set("role", value)}
          />
        </>
      ) : null}

      {entity === "check_in" ? (
        <>
          <Field label="Date" type="date" value={str("checkInDate")} onChange={(value) => set("checkInDate", value)} />
          <Field label="Sleep hours" value={str("sleepHours")} onChange={(value) => set("sleepHours", value === "" ? null : Number(value))} />
          <Rating label="Sleep quality" value={str("sleepQuality")} onChange={(value) => set("sleepQuality", Number(value))} />
          <Rating label="Morning rating" value={str("morningRating")} onChange={(value) => set("morningRating", Number(value))} />
          <Select
            label="Stress"
            value={str("stressLevel")}
            options={Object.entries(STRESS_LABELS).map(([id, label]) => ({ id, label: `${id} · ${label}` }))}
            onChange={(value) => set("stressLevel", Number(value))}
          />
          <Rating label="Energy" value={str("energyLevel")} onChange={(value) => set("energyLevel", Number(value))} />
          <Rating label="Focus" value={str("focusLevel")} onChange={(value) => set("focusLevel", Number(value))} />
          <Area label="Notes" value={str("notes")} onChange={(value) => set("notes", value)} />
        </>
      ) : null}

      {entity === "payout" ? (
        <>
          <SearchSelect label="Account" value={str("accountID")} options={lookups.accounts} onChange={(value) => set("accountID", value)} />
          <Field label="Amount" value={moneyAmount(record, "amount")?.toString() ?? ""} onChange={(value) => onChange(setMoney(record, "amount", value))} />
          <Field label="Date" type="datetime-local" value={toDateTimeLocal(record.payoutDate)} onChange={(value) => set("payoutDate", fromDateTimeLocal(value))} />
          <Area label="Note" value={str("note")} onChange={(value) => set("note", value || null)} />
          <DemoMediaField
            label="Image"
            url={str("imageURL")}
            entityType="payout"
            entityId={str("id")}
            kind="image"
            onChange={(url) => set("imageURL", url || null)}
          />
        </>
      ) : null}

      {entity === "vault_folder" ? (
        <Field label="Folder name" value={str("name")} onChange={(value) => set("name", value)} />
      ) : null}

      {entity === "vault_item" ? <VaultFields record={record} lookups={lookups} onChange={onChange} /> : null}
    </div>
  )
}

const emotionOptions = TRADE_EMOTIONS.map((emotion) => ({ id: emotion, label: emotion }))

function ActivityFields({
  record,
  lookups,
  onChange,
}: {
  record: DemoRecord
  lookups: DemoLookups
  onChange: (record: DemoRecord) => void
}) {
  const kind = text(record.kind) || "like"
  const set = (path: string, value: unknown) => onChange(writePath(record, path, value))
  return (
    <>
      <Select
        label="Type"
        value={kind}
        options={ACTIVITY_KINDS.map((item) => ({ id: item.value, label: item.label }))}
        onChange={(value) => {
          let next = writePath(record, "kind", value)
          next = writePath(next, "title", value.replaceAll("_", " "))
          if (value === "trading_report") next = writePath(next, "reportID", "monthly_last")
          if (value === "room_mention" && lookups.rooms[0]) next = writePath(next, "roomID", lookups.rooms[0].id)
          if (value !== "like" && value !== "comment" && value !== "system") next = writePath(next, "tradeID", null)
          onChange(next)
        }}
      />
      {kind !== "trading_report" && kind !== "system" ? (
        <SearchSelect
          label={kind === "follow" ? "Opens this profile" : "Actor"}
          value={text(record.actorProfileID)}
          options={lookups.profiles}
          allowEmpty={kind === "system"}
          onChange={(value) => set("actorProfileID", value || null)}
        />
      ) : null}
      {kind === "like" || kind === "comment" || kind === "system" ? (
        <SearchSelect
          label="Trade"
          value={text(record.tradeID)}
          options={lookups.trades}
          allowEmpty
          emptyLabel="No trade"
          onChange={(value) => set("tradeID", value || null)}
        />
      ) : null}
      {kind === "like" || kind === "comment" ? (
        <SearchSelect label="Post" value={text(record.postID)} options={lookups.posts} allowEmpty emptyLabel="No post" onChange={(value) => set("postID", value || null)} />
      ) : null}
      {kind === "room_mention" ? (
        <SearchSelect label="Room" value={text(record.roomID)} options={lookups.rooms} onChange={(value) => set("roomID", value)} />
      ) : null}
      {kind === "trading_report" ? (
        <p className="text-xs text-gray-400">This opens the monthly report. The report id stays monthly_last.</p>
      ) : null}
      <Area label="Text" value={text(record.body)} onChange={(value) => set("body", value)} />
      <Field label="Time" type="datetime-local" value={toDateTimeLocal(record.createdAt)} onChange={(value) => set("createdAt", fromDateTimeLocal(value))} />
    </>
  )
}

function SharedPicker({
  record,
  lookups,
  onChange,
  room,
}: {
  record: DemoRecord
  lookups: DemoLookups
  onChange: (record: DemoRecord) => void
  room: boolean
}) {
  const shared = sharedContentId(record)
  const attached = text(record.attachedTradeID)
  const current = room
    ? attached
      ? `trade:${attached}`
      : ""
    : shared
      ? `${shared.kind}:${shared.id}`
      : ""
  const options = [
    ...lookups.trades.map((item) => ({ id: `trade:${item.id}`, label: `Trade · ${item.label}` })),
    ...lookups.posts.map((item) => ({ id: `feedPost:${item.id}`, label: `Post · ${item.label}` })),
    ...lookups.achievements.map((item) => ({ id: `achievementPost:${item.id}`, label: `Achievement · ${item.label}` })),
    ...lookups.clips.map((item) => ({ id: `reel:${item.id}`, label: `Clip · ${item.label}` })),
  ]
  return (
    <SearchSelect
      label="Shared content"
      value={current}
      options={options}
      allowEmpty
      emptyLabel="Nothing shared"
      onChange={(value) => {
        if (room) {
          const tradeID = value.startsWith("trade:") ? value.slice("trade:".length) : ""
          onChange(writePath(record, "attachedTradeID", tradeID || null))
          return
        }
        if (!value) {
          onChange(writePath(writePath(record, "sharedContent", null), "kind", "text"))
          return
        }
        const [kind, id] = value.split(":")
        const messageKind =
          kind === "trade" ? "tradeShare" : kind === "feedPost" ? "post" : kind === "achievementPost" ? "achievement_post" : "reel"
        let next = writePath(record, "sharedContent", sharedContent(kind as "trade", id))
        next = writePath(next, "kind", messageKind)
        onChange(next)
      }}
    />
  )
}

function VaultFields({
  record,
  lookups,
  onChange,
}: {
  record: DemoRecord
  lookups: DemoLookups
  onChange: (record: DemoRecord) => void
}) {
  const ref = record.ref && typeof record.ref === "object" ? (record.ref as DemoRecord) : {}
  const currentType = text(ref.contentType) || "trade"
  const currentID = text(ref.contentID)
  const options =
    currentType === "trade"
      ? lookups.trades
      : currentType === "reel"
        ? lookups.clips
        : currentType === "achievement"
          ? lookups.achievements
          : lookups.posts
  const folders = Array.isArray(record.folderIDs) ? (record.folderIDs as unknown[]).map(String) : []
  return (
    <>
      <Select
        label="Saved item"
        value={currentType}
        options={[
          { id: "trade", label: "Trade" },
          { id: "feed_post", label: "Post" },
          { id: "reel", label: "Clip" },
          { id: "achievement", label: "Achievement" },
        ]}
        onChange={(value) => onChange(writePath(record, "ref", { contentType: value, contentID: "" }))}
      />
      <SearchSelect
        label="Target"
        value={currentID}
        options={options}
        onChange={(value) => onChange(writePath(record, "ref", { contentType: currentType, contentID: value }))}
      />
      <p className="text-xs text-gray-400">Folders</p>
      {lookups.folders.map((folder) => (
        <label key={folder.id} className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={folders.includes(folder.id)}
            onChange={(event) => {
              const next = event.target.checked ? [...folders, folder.id] : folders.filter((id) => id !== folder.id)
              onChange(writePath(record, "folderIDs", next))
            }}
          />
          {folder.label}
        </label>
      ))}
    </>
  )
}

function Field({
  label,
  value,
  onChange,
  type = "text",
}: {
  label: string
  value: string
  onChange: (value: string) => void
  type?: string
}) {
  return (
    <label className="block text-xs text-gray-400">
      {label}
      <input className={inputClass} type={type} value={value} onChange={(event) => onChange(event.target.value)} />
    </label>
  )
}

function Area({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  return (
    <label className="block text-xs text-gray-400">
      {label}
      <textarea className={`${inputClass} min-h-20`} value={value} onChange={(event) => onChange(event.target.value)} />
    </label>
  )
}

function Check({ label, checked, onChange }: { label: string; checked: boolean; onChange: (value: boolean) => void }) {
  return (
    <label className="flex items-center gap-2 text-sm text-gray-200">
      <input type="checkbox" checked={checked} onChange={(event) => onChange(event.target.checked)} />
      {label}
    </label>
  )
}

function Rating({ label, value, onChange }: { label: string; value: string; onChange: (value: string) => void }) {
  return (
    <Select
      label={label}
      value={value || "3"}
      options={[1, 2, 3, 4, 5].map((rating) => ({ id: String(rating), label: String(rating) }))}
      onChange={onChange}
    />
  )
}

function Select({
  label,
  value,
  options,
  onChange,
  allowEmpty = false,
}: {
  label: string
  value: string
  options: DemoOption[]
  onChange: (value: string) => void
  allowEmpty?: boolean
}) {
  return (
    <label className="block text-xs text-gray-400">
      {label}
      <select className={inputClass} value={value} onChange={(event) => onChange(event.target.value)}>
        {allowEmpty ? <option value="">None</option> : null}
        {options.map((option) => (
          <option key={option.id} value={option.id}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  )
}

function SearchSelect({
  label,
  value,
  options,
  onChange,
  allowEmpty = false,
  emptyLabel = "None",
}: {
  label: string
  value: string
  options: DemoOption[]
  onChange: (value: string) => void
  allowEmpty?: boolean
  emptyLabel?: string
}) {
  const [query, setQuery] = useState("")
  const needle = query.trim().toLowerCase()
  const filtered = options.filter(
    (option) => option.id === value || option.label.toLowerCase().includes(needle)
  )
  return (
    <label className="block text-xs text-gray-400">
      {label}
      <input
        className={inputClass}
        placeholder="Search"
        value={query}
        onChange={(event) => setQuery(event.target.value)}
      />
      <select className={inputClass} value={value} onChange={(event) => onChange(event.target.value)}>
        {allowEmpty ? <option value="">{emptyLabel}</option> : null}
        {filtered.map((option) => (
          <option key={option.id} value={option.id}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  )
}
