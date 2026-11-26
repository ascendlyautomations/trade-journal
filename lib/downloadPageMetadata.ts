import type { Metadata } from "next"
import { DEFAULT_TWITTER_CARD, SITE_NAME, SITE_URL } from "@/lib/site"

/** Shipped iOS `AppIcon.appiconset` (1024×1024), no marketing frame. */
export const DOWNLOAD_OG_IMAGE_PATH = "/ios-app-icon.png"
export const DOWNLOAD_OG_IMAGE_SIZE = 1024

export const DOWNLOAD_PAGE_TITLE = "TradeTraxs"
export const DOWNLOAD_PAGE_DESCRIPTION = "Social Day Trading Platform"

export const IOS_APP_STORE_DOWNLOAD_URL =
  "https://apps.apple.com/us/app/tradetraxs/id6808723069"

export const DOWNLOAD_PAGE_METADATA: Metadata = {
  title: { absolute: DOWNLOAD_PAGE_TITLE },
  description: DOWNLOAD_PAGE_DESCRIPTION,
  icons: {
    icon: [
      { url: "/favicon.ico" },
      {
        url: DOWNLOAD_OG_IMAGE_PATH,
        type: "image/png",
        sizes: `${DOWNLOAD_OG_IMAGE_SIZE}x${DOWNLOAD_OG_IMAGE_SIZE}`,
      },
    ],
    apple: [
      {
        url: DOWNLOAD_OG_IMAGE_PATH,
        sizes: `${DOWNLOAD_OG_IMAGE_SIZE}x${DOWNLOAD_OG_IMAGE_SIZE}`,
        type: "image/png",
      },
    ],
  },
  alternates: {
    canonical: "/download",
  },
  openGraph: {
    type: "website",
    url: `${SITE_URL}/download`,
    title: DOWNLOAD_PAGE_TITLE,
    description: DOWNLOAD_PAGE_DESCRIPTION,
    siteName: SITE_NAME,
    locale: "en_US",
    images: [
      {
        url: DOWNLOAD_OG_IMAGE_PATH,
        width: DOWNLOAD_OG_IMAGE_SIZE,
        height: DOWNLOAD_OG_IMAGE_SIZE,
        alt: DOWNLOAD_PAGE_TITLE,
      },
    ],
  },
  twitter: {
    card: DEFAULT_TWITTER_CARD,
    title: DOWNLOAD_PAGE_TITLE,
    description: DOWNLOAD_PAGE_DESCRIPTION,
    images: [DOWNLOAD_OG_IMAGE_PATH],
  },
}