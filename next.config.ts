import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";

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

/** Proto + SSL assets required by every Rithmic WSS/protocol route on Vercel. */
const RITHMIC_RUNTIME_ASSET_INCLUDES = [
  "./third_party/rithmic/0.89.0.0/proto/**/*.proto",
  "./third_party/rithmic/0.89.0.0/samples/samples.py/base.proto",
  "./lib/integrations/rithmic/rithmic_ssl_cert_auth_params",
] as const

const nextConfig: NextConfig = {
  serverExternalPackages: ["ws", "protobufjs"],
  outputFileTracingIncludes: {
    // Phase 1 lab discovery
    "/api/integrations/rithmic/phase1/discovery": [...RITHMIC_RUNTIME_ASSET_INCLUDES],
    // Production user connect + import (same asset set)
    "/api/integrations/rithmic/connect": [...RITHMIC_RUNTIME_ASSET_INCLUDES],
    "/api/integrations/rithmic/import/run": [...RITHMIC_RUNTIME_ASSET_INCLUDES],
    "/api/integrations/rithmic/connections/[connectionId]/accounts/[mappingId]/sync": [
      ...RITHMIC_RUNTIME_ASSET_INCLUDES,
    ],
    // Shared broker batch import may invoke Rithmic sync
    "/api/integrations/broker/import/run": [...RITHMIC_RUNTIME_ASSET_INCLUDES],
  },
  images: {
    qualities: [75, 85, 100],
    deviceSizes: [640, 828, 1200, 1920],
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
  async headers() {
    return [
      {
        source: "/favicon.ico",
        headers: [
          {
            key: "Cache-Control",
            value: "public, max-age=31536000, immutable",
          },
        ],
      },
      {
        source: "/logo.png",
        headers: [
          {
            key: "Cache-Control",
            value: "public, max-age=31536000, immutable",
          },
        ],
      },
    ]
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