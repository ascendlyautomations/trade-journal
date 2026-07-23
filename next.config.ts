import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";
import { resolveAllowedDevOrigins } from "./lib/devServerLanHost";

function supabaseStorageHostname(): string | undefined {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  if (!url) return undefined
  try {
    return new URL(url).hostname
  } catch {
    return undefined
  }
}

const supabaseHost = supabaseStorageHostname()
const allowedDevOrigins = resolveAllowedDevOrigins()

const nextConfig: NextConfig = {
  // Capacitor iOS loads http://<LAN-IP>:3000. Without this, Next 16 returns
  // 403 for /_next/* fetches that send Origin: http://<LAN-IP>:3000 — which
  // breaks post-login client navigation (dynamic chunk loads) on device.
  ...(allowedDevOrigins.length > 0 ? { allowedDevOrigins } : {}),
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    qualities: [75, 85, 100],
    remotePatterns: [
      {
        protocol: "https",
        hostname: "picsum.photos",
        pathname: "/**",
      },
      ...(supabaseHost
        ? [
            {
              protocol: "https" as const,
              hostname: supabaseHost,
              pathname: "/storage/v1/**",
            },
          ]
        : []),
    ],
  },
  async redirects() {
    return [
      { source: "/input-trade", destination: "/app", permanent: false },
      { source: "/input", destination: "/app", permanent: false },
      { source: "/trade-history", destination: "/trades", permanent: false },
      { source: "/ai", destination: "/analyst", permanent: false },
      { source: "/trade-rooms", destination: "/community", permanent: false },
      {
        source: "/affiliate/connect/refresh",
        destination: "/affiliate/payout-setup/refresh",
        permanent: false,
      },
      {
        source: "/affiliate/connect/return",
        destination: "/affiliate/payout-setup/return",
        permanent: false,
      },
    ]
  },
};

const sentryBuildOptions = {
  org: process.env.SENTRY_ORG,
  project: process.env.SENTRY_PROJECT,
  silent: !process.env.CI,
  ...(process.env.SENTRY_AUTH_TOKEN
    ? {
        authToken: process.env.SENTRY_AUTH_TOKEN,
        widenClientFileUpload: true,
      }
    : {}),
};

export default withSentryConfig(nextConfig, sentryBuildOptions);