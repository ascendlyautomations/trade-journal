import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  typescript: {
    ignoreBuildErrors: true,
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

export default nextConfig;