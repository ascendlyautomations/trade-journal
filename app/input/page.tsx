import { redirect } from "next/navigation"

/** Legacy deep-link path — trade entry lives at `/app`. */
export default function InputPage() {
  redirect("/app")
}
