#!/usr/bin/env node
/**
 * Build realistic300-full-isolation.json from email spec + operator UUID map.
 * Does not call production.
 */
import { readFileSync, writeFileSync } from "node:fs"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const specPath = join(root, "fixtures/realistic300-full-isolation.email-spec.json")
const mapPath = join(root, "fixtures/realistic300-full-isolation.uuid-map.json")
const outPath = join(root, "fixtures/realistic300-full-isolation.json")

function pairKey(a, b) {
  const x = [a.trim().toLowerCase(), b.trim().toLowerCase()].sort()
  return x.join("|")
}

function main() {
  const spec = JSON.parse(readFileSync(specPath, "utf8"))
  const map = JSON.parse(readFileSync(mapPath, "utf8"))

  const directConversations = []
  for (const pair of spec.directConversationPairs) {
    const key = pairKey(pair[0], pair[1])
    const id = map.directConversations?.[key] || map.directConversations?.[pair.join("|")]
    if (!id) {
      throw new Error(`Missing UUID for DM pair ${pair[0]} ↔ ${pair[1]} (key ${key})`)
    }
    directConversations.push({
      id: String(id).trim(),
      participantEmails: [pair[0], pair[1]],
    })
  }

  const tradeRooms = []
  for (const room of spec.tradeRooms) {
    const id = map.tradeRooms?.[room.key]
    if (!id) {
      throw new Error(`Missing UUID for trade room key ${room.key}`)
    }
    tradeRooms.push({
      id: String(id).trim(),
      sectionId: room.sectionId ?? map.tradeRoomSections?.[room.key] ?? null,
      memberEmails: room.memberEmails,
    })
  }

  const fixture = {
    schemaVersion: 1,
    tag: spec.tag,
    directConversations,
    tradeRooms,
    inboxRealtimeConversationIds: [],
  }

  writeFileSync(outPath, JSON.stringify(fixture, null, 2) + "\n")
  const oneLine = JSON.stringify(fixture)
  console.log(`Wrote ${outPath}`)
  console.log("")
  console.log("# Add to loadtest/.env.production-perf:")
  console.log(`LOADTEST_REALISTIC300_FULL_FIXTURE_JSON='${oneLine.replace(/'/g, "'\\''")}'`)
  if (process.argv.includes("--print-env")) {
    console.log("")
    console.log(oneLine)
  }
}

main()
