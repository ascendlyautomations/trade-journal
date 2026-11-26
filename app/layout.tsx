import type { Metadata, Viewport } from "next"
import { headers } from "next/headers"
import type { ReactNode } from "react"
import MinimalPublicRootLayout from "./MinimalPublicRootLayout"
import { isMinimalPublicDocumentRoute } from "@/lib/authRoutes"
import {
  DEFAULT_OG_IMAGE_ALT,
  DEFAULT_OG_IMAGE_PATH,
  DEFAULT_SITE_DESCRIPTION,
  HOME_PAGE_TITLE,
  DEFAULT_TWITTER_CARD,
  OG_IMAGE_HEIGHT,
  OG_IMAGE_WIDTH,
  SITE_KEYWORDS,
  SITE_NAME,
  SITE_URL,
  TWITTER_HANDLE,
} from "@/lib/site"

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: {
    default: SITE_NAME,
    template: `%s | ${SITE_NAME}`,
  },
  description: DEFAULT_SITE_DESCRIPTION,
  keywords: [...SITE_KEYWORDS],
  applicationName: SITE_NAME,
  authors: [{ name: SITE_NAME, url: SITE_URL }],
  creator: SITE_NAME,
  publisher: SITE_NAME,
  formatDetection: {
    email: false,
    address: false,
    telephone: false,
  },
  icons: {
    icon: [
      { url: "/favicon.ico" },
      { url: "/logo.png", type: "image/png", sizes: "512x512" },
    ],
    apple: [{ url: "/logo.png", sizes: "180x180", type: "image/png" }],
  },
  manifest: "/manifest.webmanifest",
  alternates: {
    canonical: "/",
  },
  openGraph: {
    type: "website",
    locale: "en_US",
    siteName: SITE_NAME,
    title: HOME_PAGE_TITLE,
    description: DEFAULT_SITE_DESCRIPTION,
    url: SITE_URL,
    images: [
      {
        url: DEFAULT_OG_IMAGE_PATH,
        width: OG_IMAGE_WIDTH,
        height: OG_IMAGE_HEIGHT,
        alt: DEFAULT_OG_IMAGE_ALT,
      },
    ],
  },
  twitter: {
    card: DEFAULT_TWITTER_CARD,
    site: TWITTER_HANDLE,
    creator: TWITTER_HANDLE,
    title: HOME_PAGE_TITLE,
    description: DEFAULT_SITE_DESCRIPTION,
    images: [DEFAULT_OG_IMAGE_PATH],
  },
  ...(process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION
    ? {
        verification: {
          google: process.env.NEXT_PUBLIC_GOOGLE_SITE_VERIFICATION,
        },
      }
    : {}),
}

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 1,
  viewportFit: "cover",
  themeColor: "#0b1f3a",
}

export default async function RootLayout({
  children,
}: Readonly<{
  children: ReactNode
}>) {
  const pathname = (await headers()).get("x-pathname") ?? ""
  if (isMinimalPublicDocumentRoute(pathname)) {
    return <MinimalPublicRootLayout>{children}</MinimalPublicRootLayout>
  }
  const { default: AppRootLayout } = await import("./AppRootLayout")
  return <AppRootLayout>{children}</AppRootLayout>
}