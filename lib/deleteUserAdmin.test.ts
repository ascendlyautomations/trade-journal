const assert = require("node:assert/strict")
const { describe, it } = require("node:test")
const {
  AdminUserDeletionError,
  assertAdminCanDeleteTarget,
} = require("./deleteUserAdmin.ts")

describe("assertAdminCanDeleteTarget", () => {
  it("blocks self-delete", async () => {
    const supabase = {
      from: () => ({
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({ data: null }),
          }),
        }),
      }),
    }

    await assert.rejects(
      () => assertAdminCanDeleteTarget(supabase as never, "admin-1", "admin-1"),
      (err: unknown) => {
        assert.ok(err instanceof AdminUserDeletionError)
        assert.equal(err.code, "SELF_DELETE")
        return true
      }
    )
  })

  it("blocks admin target accounts", async () => {
    const supabase = {
      from: () => ({
        select: () => ({
          eq: () => ({
            maybeSingle: async () => ({ data: { user_id: "target-admin" } }),
          }),
        }),
      }),
    }

    await assert.rejects(
      () =>
        assertAdminCanDeleteTarget(supabase as never, "admin-1", "target-admin"),
      (err: unknown) => {
        assert.ok(err instanceof AdminUserDeletionError)
        assert.equal(err.code, "ADMIN_TARGET")
        return true
      }
    )
  })
})
