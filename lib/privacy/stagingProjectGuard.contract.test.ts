import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const guardPath = path.join(
  process.cwd(),
  "supabase/staging/scripts/lib/project-guard.sh"
)

describe("staging project guard", () => {
  const guard = fs.readFileSync(guardPath, "utf8")

  it("allowlists staging ref hxlcvffvyadlxcsqxxoy and blocks production fobudrkniacatvilbofw", () => {
    assert.match(guard, /TRADETRAXS_ALLOWED_STAGING_PROJECT_REF.*hxlcvffvyadlxcsqxxoy/)
    assert.match(guard, /TRADETRAXS_PRODUCTION_PROJECT_REF.*fobudrkniacatvilbofw/)
    assert.match(guard, /tradetraxs_assert_production_export_ref/)
    assert.match(guard, /tradetraxs_load_staging_local_env/)
    assert.match(guard, /tradetraxs_prepend_pg_client_path/)
  })

  it("loadtest refuses production and requires allowlisted staging ref", () => {
    const k6 = fs.readFileSync(
      path.join(process.cwd(), "loadtest/phase-a-read.js"),
      "utf8"
    )
    assert.match(k6, /ALLOWED_STAGING_PROJECT_REF = "hxlcvffvyadlxcsqxxoy"/)
    assert.match(k6, /PRODUCTION_PROJECT_REF = "fobudrkniacatvilbofw"/)
  })

  it("documents gitignored local env template", () => {
    const example = fs.readFileSync(
      path.join(process.cwd(), "supabase/staging/.env.local.example"),
      "utf8"
    )
    assert.match(example, /TRADETRAXS_STAGING_PROJECT_REF=hxlcvffvyadlxcsqxxoy/)
    for (const line of example.split("\n")) {
      const trimmed = line.trim()
      if (trimmed.startsWith("#") || trimmed === "") continue
      assert.doesNotMatch(trimmed, /service_role/i, "env template must not assign service_role keys")
    }
  })
})
