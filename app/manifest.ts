import type { MetadataRoute } from "next"
import { DEFAULT_OG_IMAGE_PATH, SITE_NAME, SITE_URL } from "@/lib/site"

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: SITE_NAME,
    short_name: SITE_NAME,
    description:
      "AI-powered trading journal app for futures and active traders.",
    start_url: "/",
    display: "standalone",
    background_color: "#0f172a",
    theme_color: "#0f172a",
    lang: "en-US",
    scope: "/",
    icons: [
      {
        src: "/logo.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any",
      },
      {
        src: "/logo.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
    screenshots: [
      {
        src: DEFAULT_OG_IMAGE_PATH,
        sizes: "1200x630",
        type: "image/png",
        form_factor: "wide",
        label: `${SITE_NAME} trading journal`,
      },
    ],
    id: SITE_URL,
  }
}
