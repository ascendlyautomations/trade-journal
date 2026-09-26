import { notFound } from "next/navigation"
import ContentImageV2Harness from "./ContentImageV2Harness"

/** Development-only crop harness. Not a production upload route. */
export default function ContentImageV2DevPage() {
  if (process.env.NODE_ENV === "production") {
    notFound()
  }
  return <ContentImageV2Harness />
}
