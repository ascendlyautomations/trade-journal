import { redirect } from "next/navigation"

/** Stories have no dedicated deep-link surface — open the feed stories bar. */
export default function StoryUniversalRedirect() {
  redirect("/feed")
}
