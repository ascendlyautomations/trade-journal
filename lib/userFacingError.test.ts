import assert from "node:assert/strict"
import { test } from "node:test"
import {
  toUserFacingErrorMessage,
  USER_FACING_ERROR_MESSAGES,
} from "./userFacingError.ts"

test("maps duplicate key to friendly username message", () => {
  const msg = toUserFacingErrorMessage({
    code: "23505",
    message: 'duplicate key value violates unique constraint "profiles_username_key"',
  })
  assert.equal(msg, USER_FACING_ERROR_MESSAGES.USERNAME_TAKEN)
})

test("maps P0001 free plan trade limit", () => {
  const msg = toUserFacingErrorMessage({
    code: "P0001",
    message: "You've reached the Free plan limit of 3 trades every 24 hours.",
  })
  assert.equal(msg, USER_FACING_ERROR_MESSAGES.FREE_PLAN_DAILY_TRADE_LIMIT)
})

test("maps P0001 free plan clip limit", () => {
  const msg = toUserFacingErrorMessage({
    code: "P0001",
    message: "FREE_PLAN_DAILY_CLIP_LIMIT",
  })
  assert.equal(msg, USER_FACING_ERROR_MESSAGES.FREE_PLAN_DAILY_CLIP_LIMIT)
})

test("maps P0001 free plan DM limit", () => {
  const msg = toUserFacingErrorMessage({
    code: "P0001",
    message: "FREE_PLAN_DAILY_DM_LIMIT",
  })
  assert.equal(msg, USER_FACING_ERROR_MESSAGES.FREE_PLAN_DAILY_DM_LIMIT)
})

test("maps foreign key violation", () => {
  const msg = toUserFacingErrorMessage({
    code: "23503",
    message: "insert or update on table violates foreign key constraint",
  })
  assert.equal(msg, USER_FACING_ERROR_MESSAGES.ACTION_FAILED)
})

test("maps failed to fetch", () => {
  assert.equal(
    toUserFacingErrorMessage("Failed to fetch"),
    USER_FACING_ERROR_MESSAGES.NETWORK_ERROR
  )
})

test("maps upload status noise", () => {
  assert.equal(
    toUserFacingErrorMessage("Upload failed (500)."),
    USER_FACING_ERROR_MESSAGES.FILE_UPLOAD_FAILED
  )
})

test("maps missing stripe config", () => {
  const msg = toUserFacingErrorMessage("Missing STRIPE_SECRET_KEY")
  assert.equal(msg, USER_FACING_ERROR_MESSAGES.BILLING_UNAVAILABLE)
})

test("maps network errors", () => {
  assert.equal(
    toUserFacingErrorMessage(new TypeError("Failed to fetch")),
    USER_FACING_ERROR_MESSAGES.NETWORK_ERROR
  )
})

test("maps permission denied", () => {
  const msg = toUserFacingErrorMessage({ message: "permission denied for table profiles" })
  assert.equal(msg, USER_FACING_ERROR_MESSAGES.UNAUTHORIZED)
})

test("maps jwt expired", () => {
  const msg = toUserFacingErrorMessage({ message: "JWT expired" })
  assert.equal(msg, USER_FACING_ERROR_MESSAGES.SESSION_EXPIRED)
})

test("passes through human-readable account name conflict", () => {
  const msg = toUserFacingErrorMessage({
    message: "An account with this name already exists",
  })
  assert.equal(msg, "An account with this name already exists.")
})
