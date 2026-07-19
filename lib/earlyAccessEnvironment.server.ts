import "server-only"

export type EarlyAccessEnvironment =
  | "production"
  | "preview"
  | "development"

export function resolveEarlyAccessEnvironment(): EarlyAccessEnvironment {
  const vercelEnv = String(process.env.VERCEL_ENV ?? "").toLowerCase()
  if (vercelEnv === "production") return "production"
  if (vercelEnv === "preview") return "preview"
  return "development"
}
