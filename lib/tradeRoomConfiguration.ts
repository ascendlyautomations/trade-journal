export const TRADE_ROOM_CATEGORIES = [
  { value: "general", label: "General" },
  { value: "futures", label: "Futures" },
  { value: "options", label: "Options" },
  { value: "stocks", label: "Stocks" },
  { value: "crypto", label: "Crypto" },
  { value: "forex", label: "Forex" },
  { value: "prop_firms", label: "Prop Firms" },
  { value: "day_trading", label: "Day Trading" },
  { value: "swing_trading", label: "Swing Trading" },
] as const

export type TradeRoomCategory = (typeof TRADE_ROOM_CATEGORIES)[number]["value"]

export type TradeRoomVisibility = "public" | "private"
export type TradeRoomJoinPolicy = "open" | "approval"

export type TradeRoomDraftChannel = {
  id: string
  name: string
  allowMembersChat: boolean
}

export type TradeRoomConfiguration = {
  name: string
  description: string
  imageUrl: string | null
  category: TradeRoomCategory
  discoveryTags: string[]
  visibility: TradeRoomVisibility
  showsOnProfile: boolean
  joinPolicy: TradeRoomJoinPolicy
  rules: string
  membersCanMessage: boolean
  membersCanShareTrades: boolean
  membersCanShareMedia: boolean
  channels: TradeRoomDraftChannel[]
}

export const TRADE_ROOM_PRESET_DISCOVERY_TAGS = [
  "Scalping",
  "Day Trading",
  "Swing Trading",
  "Futures",
  "Options",
  "Prop Firms",
  "Technical Analysis",
  "Trading Psychology",
  "Beginners",
] as const

export const TRADE_ROOM_VALIDATION = {
  nameMaxLength: 100,
  descriptionMaxLength: 500,
  rulesMaxLength: 2000,
  maxDiscoveryTags: 5,
  maxChannels: 5,
  channelNameMaxLength: 64,
} as const

export function defaultTradeRoomDraft(username?: string | null): TradeRoomConfiguration {
  const trimmed = String(username ?? "").trim()
  const defaultName = trimmed ? `${trimmed}'s Room` : ""
  return {
    name: defaultName,
    description: "",
    imageUrl: null,
    category: "general",
    discoveryTags: [],
    visibility: "public",
    showsOnProfile: true,
    joinPolicy: "open",
    rules: "",
    membersCanMessage: true,
    membersCanShareTrades: true,
    membersCanShareMedia: true,
    channels: [
      {
        id: crypto.randomUUID(),
        name: "General",
        allowMembersChat: true,
      },
    ],
  }
}

export function normalizedChannelName(raw: string): string {
  return raw.trim()
}

export function hasDuplicateChannelNames(channels: TradeRoomDraftChannel[]): boolean {
  const seen = new Set<string>()
  for (const channel of channels) {
    const key = normalizedChannelName(channel.name).toLowerCase()
    if (!key) continue
    if (seen.has(key)) return true
    seen.add(key)
  }
  return false
}

export function effectiveJoinPolicy(config: TradeRoomConfiguration): TradeRoomJoinPolicy {
  if (config.visibility === "private") return "approval"
  return config.joinPolicy
}

export function roomRequiresJoinApproval(room: {
  join_policy?: string | null
  is_private?: boolean | null
}): boolean {
  if (room.is_private) return true
  return String(room.join_policy ?? "open").toLowerCase() === "approval"
}

export function validateTradeRoomConfiguration(
  config: TradeRoomConfiguration,
  options?: { skipChannels?: boolean }
): string | null {
  const name = config.name.trim()
  if (!name) return "Room name is required."
  if (name.length > TRADE_ROOM_VALIDATION.nameMaxLength) {
    return `Room name must be ${TRADE_ROOM_VALIDATION.nameMaxLength} characters or fewer.`
  }

  const description = config.description.trim()
  if (description.length > TRADE_ROOM_VALIDATION.descriptionMaxLength) {
    return `Description must be ${TRADE_ROOM_VALIDATION.descriptionMaxLength} characters or fewer.`
  }

  const rules = config.rules.trim()
  if (rules.length > TRADE_ROOM_VALIDATION.rulesMaxLength) {
    return `Room rules must be ${TRADE_ROOM_VALIDATION.rulesMaxLength} characters or fewer.`
  }

  if (config.discoveryTags.length > TRADE_ROOM_VALIDATION.maxDiscoveryTags) {
    return `Choose up to ${TRADE_ROOM_VALIDATION.maxDiscoveryTags} tags.`
  }

  if (!options?.skipChannels) {
    if (config.channels.length === 0) return "Add at least one sub-room."
    if (config.channels.length > TRADE_ROOM_VALIDATION.maxChannels) {
      return `You can have up to ${TRADE_ROOM_VALIDATION.maxChannels} sub-rooms.`
    }

    for (const channel of config.channels) {
      const channelName = normalizedChannelName(channel.name)
      if (!channelName) return "Sub-room names cannot be blank."
      if (channelName.length > TRADE_ROOM_VALIDATION.channelNameMaxLength) {
        return `Sub-room names must be ${TRADE_ROOM_VALIDATION.channelNameMaxLength} characters or fewer.`
      }
    }

    if (hasDuplicateChannelNames(config.channels)) {
      return "Sub-room names must be unique."
    }
  }

  return null
}

export function tradeRoomVisibilitySummary(visibility: TradeRoomVisibility): string {
  return visibility === "public"
    ? "Discoverable in Suggested, Popular, and Explore."
    : "Hidden from public discovery. Invite or link access only."
}
