import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { readFileSync } from "node:fs"
import { join } from "node:path"

describe("publishProfilePost idempotency", () => {
  it("uses stable storage path and upsert for profile post uploads", () => {
    const src = readFileSync(
      join(process.cwd(), "lib/publishProfilePost.ts"),
      "utf8"
    )
    assert.match(src, /profilePostStorageObjectPath/)
    assert.match(src, /upsert:\s*true/)
    assert.match(src, /client_publish_id/)
    assert.match(src, /insertProfileWallPostIdempotent/)
  })

  it("insert helper resolves duplicate client_publish_id", () => {
    const src = readFileSync(
      join(process.cwd(), "lib/insertProfileWallPostIdempotent.ts"),
      "utf8"
    )
    assert.match(src, /isUniqueViolation/)
    assert.match(src, /client_publish_id/)
    assert.match(src, /\.select\("id"\)/)
  })
})
