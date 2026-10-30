/**
 * Isolation fixture for realistic300_full — only perf-owned DMs and rooms.
 */

export function parseRealistic300FullFixture(rawJson) {
  let data
  try {
    data = JSON.parse(rawJson)
  } catch (e) {
    throw new Error("LOADTEST_REALISTIC300_FULL_FIXTURE_JSON is not valid JSON: " + e.message)
  }
  if (!data || data.schemaVersion !== 1) {
    throw new Error("Fixture schemaVersion must be 1")
  }
  if (!data.tag || String(data.tag).indexOf("loadtest") === -1) {
    throw new Error("Fixture must include a loadtest tag identifier")
  }
  const directConversations = Array.isArray(data.directConversations) ? data.directConversations : []
  const tradeRooms = Array.isArray(data.tradeRooms) ? data.tradeRooms : []
  if (directConversations.length === 0 && tradeRooms.length === 0) {
    throw new Error("Fixture needs at least one directConversations or tradeRooms entry")
  }
  for (let i = 0; i < directConversations.length; i++) {
    const c = directConversations[i]
    if (!c.id || !Array.isArray(c.participantEmails) || c.participantEmails.length < 2) {
      throw new Error("directConversations[" + i + "] needs id + participantEmails (>=2)")
    }
  }
  for (let j = 0; j < tradeRooms.length; j++) {
    const r = tradeRooms[j]
    if (!r.id || !Array.isArray(r.memberEmails) || r.memberEmails.length === 0) {
      throw new Error("tradeRooms[" + j + "] needs id + memberEmails")
    }
  }
  const inboxRealtimeConversationIds = Array.isArray(data.inboxRealtimeConversationIds)
    ? data.inboxRealtimeConversationIds
    : directConversations.slice(0, Math.min(40, directConversations.length)).map(function (c) {
        return c.id
      })
  const memberRoomIds = tradeRooms.map(function (r) {
    return r.id
  })
  return {
    tag: data.tag,
    directConversations: directConversations,
    tradeRooms: tradeRooms,
    inboxRealtimeConversationIds: inboxRealtimeConversationIds,
    memberRoomIds: memberRoomIds,
  }
}

export function fixtureEmailsLower(fixture) {
  const set = {}
  function add(list) {
    for (let i = 0; i < list.length; i++) {
      set[String(list[i]).trim().toLowerCase()] = true
    }
  }
  for (let i = 0; i < fixture.directConversations.length; i++) {
    add(fixture.directConversations[i].participantEmails)
  }
  for (let j = 0; j < fixture.tradeRooms.length; j++) {
    add(fixture.tradeRooms[j].memberEmails)
  }
  return set
}

export function pickConversationForEmail(fixture, email) {
  const needle = String(email).trim().toLowerCase()
  const matches = []
  for (let i = 0; i < fixture.directConversations.length; i++) {
    const c = fixture.directConversations[i]
    for (let j = 0; j < c.participantEmails.length; j++) {
      if (String(c.participantEmails[j]).trim().toLowerCase() === needle) {
        matches.push(c)
        break
      }
    }
  }
  if (matches.length === 0) {
    return null
  }
  return matches[0]
}

export function pickRoomForEmail(fixture, email) {
  const needle = String(email).trim().toLowerCase()
  for (let i = 0; i < fixture.tradeRooms.length; i++) {
    const r = fixture.tradeRooms[i]
    for (let j = 0; j < r.memberEmails.length; j++) {
      if (String(r.memberEmails[j]).trim().toLowerCase() === needle) {
        return r
      }
    }
  }
  return fixture.tradeRooms.length ? fixture.tradeRooms[0] : null
}

export function buildInboxDmFilter(conversationIds) {
  const sorted = conversationIds.slice().sort()
  if (sorted.length === 0) {
    return null
  }
  if (sorted.length === 1) {
    return "conversation_id=eq." + sorted[0]
  }
  return "conversation_id=in.(" + sorted.join(",") + ")"
}

export function buildMemberRoomsFilter(roomIds) {
  const sorted = roomIds.slice().sort()
  if (sorted.length === 0) {
    return null
  }
  if (sorted.length === 1) {
    return "room_id=eq." + sorted[0]
  }
  return "room_id=in.(" + sorted.join(",") + ")"
}
