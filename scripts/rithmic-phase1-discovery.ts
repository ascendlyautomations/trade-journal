#!/usr/bin/env npx tsx
/**
 * Run Rithmic Phase 1 discovery against Rithmic Test (server env credentials).
 * Usage: RITHMIC_API_USER=... RITHMIC_API_PASSWORD=... npm run rithmic:phase1-discovery
 */
import { runRithmicPhase1Discovery } from "../lib/integrations/rithmic/runRithmicPhase1Discovery"

async function main() {
  const result = await runRithmicPhase1Discovery()
  console.log(JSON.stringify(result, null, 2))
  process.exit(result.ok ? 0 : 1)
}

main().catch((err) => {
  console.error(err instanceof Error ? err.message : err)
  process.exit(1)
})
