import type { Metadata } from "next"
import { appleSmartAppBannerContent } from "@/lib/nativeIosAppStore"

type LayoutProps = {
  children: React.ReactNode
  params: Promise<{ id: string }>
}

export async function generateMetadata({ params }: LayoutProps): Promise<Metadata> {
  const { id } = await params
  const key = decodeURIComponent(id).trim()
  const appArgument = `https://www.tradetraxs.com/room/${encodeURIComponent(key)}`
  return {
    other: {
      "apple-itunes-app": appleSmartAppBannerContent(appArgument),
    },
  }
}

export default function RoomShareLayout({ children }: LayoutProps) {
  return children
}
