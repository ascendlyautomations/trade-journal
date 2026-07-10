/** Test whether extra inbox embed columns cause query failure. */
import { createClient } from "@supabase/supabase-js"
import { readFileSync } from "fs"

const env = Object.fromEntries(
  readFileSync(".env.local", "utf8")
    .split(/\r?\n/)
    .filter((l) => l && !l.startsWith("#"))
    .map((l) => {
      const i = l.indexOf("=")
      return [l.slice(0, i), l.slice(i + 1)]
    })
)

const admin = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.SUPABASE_SERVICE_ROLE_KEY)
const anon = createClient(env.NEXT_PUBLIC_SUPABASE_URL, env.NEXT_PUBLIC_SUPABASE_ANON_KEY)

const email = "tradetraxs@gmail.com"
const { data: link } = await admin.auth.admin.generateLink({ type: "magiclink", email })
const { data: sd } = await anon.auth.verifyOtp({
  type: "magiclink",
  token_hash: link.properties.hashed_token,
})
const userId = sd.session.user.id

const variants = [
  {
    name: "inbox-full",
    select: `conversation_id, conversations (id, is_group, is_pinned, name, avatar_url, last_message, last_message_at)`,
  },
  {
    name: "inbox-no-pinned-last",
    select: `conversation_id, conversations (id, is_group, name, avatar_url, last_message_at)`,
  },
  {
    name: "inbox-flat-only",
    select: "conversation_id",
  },
]

for (const v of variants) {
  const res = await anon
    .from("conversation_participants")
    .select(v.select)
    .eq("user_id", userId)
  console.log(v.name, {
    error: res.error?.message ?? null,
    code: res.error?.code ?? null,
    rows: res.data?.length ?? 0,
  })
}
