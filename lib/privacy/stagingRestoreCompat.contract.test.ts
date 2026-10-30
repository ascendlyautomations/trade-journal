import assert from "node:assert/strict"
import { execFileSync } from "node:child_process"
import fs from "node:fs"
import os from "node:os"
import path from "node:path"
import { describe, it } from "node:test"

const root = process.cwd()
const filterPy = path.join(
  root,
  "supabase/staging/scripts/lib/split-managed-schema-dump.py"
)
const fixture = path.join(
  root,
  "supabase/staging/testfixtures/managed_raw.sample.sql"
)
const guardPath = path.join(root, "supabase/staging/scripts/lib/project-guard.sh")
const exportSh = path.join(
  root,
  "supabase/staging/scripts/export-production-schema.sh"
)
const restoreSh = path.join(
  root,
  "supabase/staging/scripts/restore-staging-schema.sh"
)

function filterFixture(inputSql: string): string {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "staging-filter-"))
  const inFile = path.join(dir, "in.sql")
  const outFile = path.join(dir, "out.sql")
  fs.writeFileSync(inFile, inputSql)
  execFileSync("python3", [filterPy, inFile, outFile])
  return fs.readFileSync(outFile, "utf8")
}

describe("staging restore compatibility", () => {
  it("filters managed dump to policies, grants, and auth signup trigger only", () => {
    const out = filterFixture(fs.readFileSync(fixture, "utf8"))
    assert.match(out, /on_auth_user_created/)
    assert.match(out, /CREATE POLICY[\s\S]*ON storage\.objects/)
    assert.match(out, /GRANT SELECT ON TABLE storage\.objects/)
    assert.doesNotMatch(out, /^CREATE TABLE auth\.users/m)
    assert.doesNotMatch(out, /^CREATE SCHEMA auth/m)
    assert.doesNotMatch(out, /^CREATE FUNCTION auth\.jwt/m)

    const dropIdx = out.indexOf("DROP TRIGGER IF EXISTS on_auth_user_created")
    const createIdx = out.indexOf("CREATE TRIGGER on_auth_user_created")
    assert.ok(dropIdx >= 0 && createIdx >= 0 && dropIdx < createIdx)
  })

  it("fails fast when filter cannot produce a safe platform hook script", () => {
    const bad = `
CREATE SCHEMA auth;
CREATE TABLE auth.users (id uuid);
ALTER TYPE auth.aal_level OWNER TO supabase_auth_admin;
`
    assert.throws(
      () => filterFixture(bad),
      (err: unknown) => {
        const msg = err instanceof Error ? err.message : String(err)
        return (
          msg.includes("unclassified managed-schema") ||
          msg.includes("missing auth.on_auth_user_created")
        )
      }
    )
  })

  it("requires handle_new_user in application artifact and ON_ERROR_STOP restore", () => {
    const guard = fs.readFileSync(guardPath, "utf8")
    assert.match(guard, /tradetraxs_validate_application_artifact/)
    assert.match(guard, /handle_new_user/)
    assert.match(guard, /tradetraxs_validate_platform_custom_artifact/)
    assert.match(guard, /on_auth_user_created/)

    const restore = fs.readFileSync(restoreSh, "utf8")
    assert.match(restore, /ON_ERROR_STOP=1/)
    assert.match(restore, /schema_application\.sql/)
    assert.match(restore, /schema_platform_custom\.sql/)
    assert.doesNotMatch(restore, /schema_baseline\.sql/)
  })

  it("export splits public/demo from managed auth/storage hooks", () => {
    const exp = fs.readFileSync(exportSh, "utf8")
    assert.match(exp, /--schema=public/)
    assert.match(exp, /--schema=demo/)
    assert.match(exp, /split-managed-schema-dump\.py/)
    assert.match(exp, /tradetraxs_validate_staging_export_artifacts/)
    assert.doesNotMatch(exp, /--schema=realtime/)
    assert.doesNotMatch(exp, /--schema=graphql_public/)
  })
})
