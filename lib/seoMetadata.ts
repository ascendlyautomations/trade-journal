import type { Metadata } from "next"
import {
  DEFAULT_OG_IMAGE_ALT,
  DEFAULT_OG_IMAGE_PATH,
  DEFAULT_SITE_DESCRIPTION,
  OG_IMAGE_HEIGHT,
  OG_IMAGE_WIDTH,
  SITE_NAME,
  SITE_URL,
} from "@/lib/site"

type BuildSeoMetadataInput = {
  /** Page title without site suffix (e.g. "Pricing"). */
  title: string
  description: string
  /** Canonical path including leading slash. Use "/" for home. */
  path: `/${string}` | "/"
  /** When false, adds noindex/nofollow (private app pages). Default true. */
  index?: boolean
  /** Override the default Open Graph image path. */
  ogImagePath?: string
  /** Use absolute title (skip " | TradeTraxs" template). */
  absoluteTitle?: string
}

const ogImageEntry = (path: string = DEFAULT_OG_IMAGE_PATH) => ({
  url: path,
  width: OG_IMAGE_WIDTH,
  height: OG_IMAGE_HEIGHT,
  alt: DEFAULT_OG_IMAGE_ALT,
})

export function buildSeoMetadata({
  title,
  description,
  path,
  index = true,
  ogImagePath = DEFAULT_OG_IMAGE_PATH,
  absoluteTitle,
}: BuildSeoMetadataInput): Metadata {
  const pageTitle = absoluteTitle ?? `${title} | ${SITE_NAME}`
  const canonicalPath = path === "/" ? "/" : path
  const url = `${SITE_URL}${canonicalPath === "/" ? "" : canonicalPath}`

  const metadata: Metadata = {
    title: absoluteTitle ? { absolute: absoluteTitle } : title,
    description,
    alternates: {
      canonical: canonicalPath,
    },
    openGraph: {
      type: "website",
      url,
      title: pageTitle,
      description,
      siteName: SITE_NAME,
      locale: "en_US",
      images: [ogImageEntry(ogImagePath)],
    },
    twitter: {
      card: "summary_large_image",
      title: pageTitle,
      description,
      images: [ogImagePath],
    },
  }

  if (!index) {
    metadata.robots = { index: false, follow: false }
  }

  return metadata
}

/** Metadata for authenticated / private app surfaces (unique title, noindex). */
export function buildAppPageMetadata(
  title: string,
  description: string,
  path: `/${string}`
): Metadata {
  return buildSeoMetadata({
    title,
    description: description || DEFAULT_SITE_DESCRIPTION,
    path,
    index: false,
  })
}

export const PRIVATE_APP_ROBOTS: Metadata["robots"] = {
  index: false,
  follow: false,
}
