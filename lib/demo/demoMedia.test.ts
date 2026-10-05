import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import test from "node:test"
import type { DemoDraft } from "./demoAdminModel.ts"
import {
  collectDemoMediaPaths,
  demoMediaObjectPath,
  humanizeDemoIssue,
  isDemoOwnedStoragePath,
  validateDemoMediaFile,
} from "./demoMedia.ts"

const png = Uint8Array.from(
  Buffer.from(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==",
    "base64"
  )
)

test("demo media paths stay inside the demo prefix", () => {
  const path = demoMediaObjectPath("trade", "demo-trade-2-0", "png", "shot")
  assert.equal(path, "demo/trade/demo-trade-2-0/shot.png")
  assert.equal(isDemoOwnedStoragePath(path), true)
  assert.equal(isDemoOwnedStoragePath("avatars/user/photo.jpg"), false)
  assert.equal(isDemoOwnedStoragePath("demo/../avatars/user/photo.jpg"), false)
  assert.equal(isDemoOwnedStoragePath("/demo/trade/id/file.png"), false)
  assert.throws(() => demoMediaObjectPath("profile", "../avatars", "png", "x"))
})

test("uploads reject empty files and accept a real png", () => {
  assert.match(
    validateDemoMediaFile(
      { name: "empty.png", type: "image/png", size: 0, bytes: new Uint8Array() },
      { entityType: "trade", kind: "image" }
    ) || "",
    /empty/i
  )
  assert.equal(
    validateDemoMediaFile(
      { name: "pixel.png", type: "image/png", size: png.byteLength, bytes: png },
      { entityType: "profile", kind: "image" }
    ),
    null
  )
})

test("cleanup only sees demo-media objects", () => {
  const paths = collectDemoMediaPaths({
    thumbnail: { id: "https://example.supabase.co/storage/v1/object/public/avatars/user/a.jpg" },
    image: { id: "https://example.supabase.co/storage/v1/object/public/demo-media/demo/trade/demo-trade-2-0/a.png" },
    note: "https://images.unsplash.com/photo.jpg",
  })
  assert.deepEqual(paths, ["demo/trade/demo-trade-2-0/a.png"])
})

test("validation issues name the Demo content instead of raw ids", () => {
  const draft = {
    profiles: [],
    accounts: [],
    trades: [],
    posts: [],
    clips: [],
    stories: [],
    achievements: [],
    activity: [{ id: "demo.activity.like", kind: "like", title: "like", body: "Alex liked your trade", tradeID: "missing" }],
    conversations: [{ id: "demo.dm.sarah", title: "Sarah Chen" }],
    messages: [{ id: "demo.dm.sarah.hello", conversationID: "demo.dm.sarah", body: "hi" }],
    rooms: [],
    channels: [],
    memberships: [],
    roomMessages: [],
    checkIns: [],
    payouts: [{ id: "demo-payout-1", amount: { amount: 10, currencyCode: "USD" } }],
    vaultFolders: [],
    vaultItems: [],
  } as unknown as DemoDraft
  assert.equal(
    humanizeDemoIssue("Activity demo.activity.like references trade missing-trade, which does not exist.", draft),
    "Activity “Alex liked your trade” points at a trade that no longer exists."
  )
  assert.equal(
    humanizeDemoIssue("Message demo.dm.sarah.hello shares trade missing-trade, which does not exist.", draft),
    "Message in “Sarah Chen” shares a trade that no longer exists."
  )
  assert.equal(
    humanizeDemoIssue("Payout demo-payout-1 references account missing, which does not exist.", draft),
    "Payout “+$10” is assigned to an account that no longer exists."
  )
})

test("demo media migration keeps visitor read and admin-only refs", () => {
  const sql = readFileSync(
    new URL("../../supabase/migrations/20261003031820_demo_media.sql", import.meta.url),
    "utf8"
  )
  assert.match(sql, /'demo-media'/)
  assert.match(sql, /demo_media_public_read/)
  assert.match(sql, /to anon, authenticated/)
  assert.doesNotMatch(sql, /demo_media_.*insert/i)
  assert.match(sql, /rpc_v1_admin_demo_media_refs/)
  assert.match(sql, /from public\.admin_users/)
  assert.match(sql, /revoke all on function public\.rpc_v1_admin_demo_media_refs\(\) from public, anon/)
  assert.match(sql, /change_summary/)
})
