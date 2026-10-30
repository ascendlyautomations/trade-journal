import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { describe, it } from "node:test"

const root = process.cwd()
const guard = fs.readFileSync(
  path.join(root, "supabase/staging/scripts/lib/project-guard.sh"),
  "utf8"
)

describe("staging full clone workflow", () => {
  it("guards production backup vs staging restore", () => {
    assert.match(guard, /tradetraxs_assert_production_backup_env/)
    assert.match(guard, /tradetraxs_assert_production_session_pooler_url/)
    assert.match(guard, /tradetraxs_assert_full_clone_restore_env/)
    assert.match(guard, /TRADETRAXS_FULL_CLONE_CONFIRM/)
    assert.match(guard, /tradetraxs_assert_production_backup_read_only_ops/)
  })

  it("configure script uses session pooler host and sslmode=require", () => {
    const cfg = fs.readFileSync(
      path.join(root, "supabase/staging/scripts/full-clone/configure-production-backup-url.sh"),
      "utf8"
    )
    assert.match(cfg, /aws-1-us-east-2\.pooler\.supabase\.com/)
    assert.match(cfg, /sslmode=require/)
    assert.match(cfg, /postgres\.\$\{TRADETRAXS_PRODUCTION_PROJECT_REF\}/)
  })

  it("restore script uses Supabase-recommended psql order", () => {
    const restore = fs.readFileSync(
      path.join(root, "supabase/staging/scripts/full-clone/restore-staging-database.sh"),
      "utf8"
    )
    assert.match(restore, /session_replication_role = replica/)
    assert.match(restore, /roles\.sql/)
    assert.match(restore, /schema\.sql/)
    assert.match(restore, /data\.sql/)
    assert.match(restore, /post-restore-hardening\.sql/)
    assert.match(restore, /backup-staging-snapshot/)
  })

  it("backup excludes vector storage tables per Supabase docs", () => {
    const backup = fs.readFileSync(
      path.join(root, "supabase/staging/scripts/full-clone/backup-production-database.sh"),
      "utf8"
    )
    assert.match(backup, /storage\.buckets_vectors/)
    assert.match(backup, /default_transaction_read_only/)
  })

  it("keeps clone env example out of git", () => {
    const gitignore = fs.readFileSync(
      path.join(root, "supabase/staging/full-clone/.gitignore"),
      "utf8"
    )
    assert.match(gitignore, /\.env\.local/)
  })
})
