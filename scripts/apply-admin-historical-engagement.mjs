#!/usr/bin/env node
/**
 * Apply admin_historical_engagement_bundle to a linked remote project.
 * Requires: `npx supabase login` (or SUPABASE_ACCESS_TOKEN).
 *
 *   npx supabase db query --remote=fobudrkniacatvilbofw \\
 *     -f supabase/migrations/20261123180000_admin_historical_engagement_bundle.sql
 */
import { readFileSync } from "fs"
import path from "path"
import { fileURLToPath } from "url"

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)))
const migration = path.join(
  root,
  "supabase/migrations/20261123180000_admin_historical_engagement_bundle.sql"
)
console.log("Apply this migration file on project fobudrkniacatvilbofw:")
console.log(migration)
console.log(readFileSync(migration, "utf8").slice(0, 120).trim() + "…")
console.log("\nAfter login: npx supabase db query --remote=fobudrkniacatvilbofw -f", migration)