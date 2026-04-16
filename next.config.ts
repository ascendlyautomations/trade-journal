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
      { source: "/payouts", destination: "/affiliate", permanent: false },
      { source: "/trade-rooms", destination: "/community", permanent: false },
    ]
  },
};

export default nextConfig;