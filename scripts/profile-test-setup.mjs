#!/usr/bin/env node
/**
 * Idempotent integration-test fixtures (follow + active story).
 * Uses service role; does not print secrets.
 */
import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "node:fs"
import { resolve } from "node:path"

function loadEnvLocal() {
  const raw = readFileSync(resolve(process.cwd(), ".env.local"), "utf8")
  const env = {}
  for (const line of raw.split(/\r?\n/)) {
    if (!line || line.startsWith("#")) continue
    const i = line.indexOf("=")
    if (i < 1) continue
    env[line.slice(0, i).trim()] = line.slice(i + 1).trim()
  }
  return env
}

const env = loadEnvLocal()
const url = env.NEXT_PUBLIC_SUPABASE_URL
const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY
const admin = createClient(url, serviceKey)

const VIEWER_USERNAME = process.env.PROFILE_TEST_OWN_USERNAME ?? "tradetraxs"
const PRIVATE_USERNAME =
  process.env.PROFILE_TEST_PRIVATE_VISIBLE_USERNAME ?? "blanchettrades"
const ACTIVE_STORY_USERNAME =
  process.env.PROFILE_TEST_ACTIVE_STORY_USERNAME ?? "tradetraxs"

async function profileId(username) {
  const { data, error } = await admin
    .from("profiles")
    .select("id")
    .eq("username", username)
    .maybeSingle()
  if (error || !data?.id) throw new Error(`profile not found: ${username}`)
  return data.id
}

const viewerId = await profileId(VIEWER_USERNAME)
const privateId = await profileId(PRIVATE_USERNAME)
const storyUserId = await profileId(ACTIVE_STORY_USERNAME)

const { error: followErr } = await admin.from("followers").upsert(
  { follower_id: viewerId, following_id: privateId },
  { onConflict: "follower_id,following_id", ignoreDuplicates: true }
)
if (followErr) throw followErr

const { data: recentStory } = await admin
  .from("stories")
  .select("id, created_at")
  .eq("user_id", storyUserId)
  .gte("created_at", new Date(Date.now() - 23 * 60 * 60 * 1000).toISOString())
  .limit(1)
  .maybeSingle()

if (!recentStory) {
  const { error: storyErr } = await admin.from("stories").insert({
    user_id: storyUserId,
    image_url: "https://example.com/test-story-phase-e2.jpg",
  })
  if (storyErr) throw storyErr
}

console.log("profile-test-setup: ok")
