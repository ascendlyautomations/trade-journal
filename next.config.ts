import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs";

const nextConfig: NextConfig = {
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    qualities: [75, 100],
    remotePatterns: [
      {
        protocol: "https",
        hostname: "picsum.photos",
        pathname: "/**",
      },
    ],
  },
  async redirects() {
    return [
      { source: "/input-trade", destination: "/app", permanent: false },
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