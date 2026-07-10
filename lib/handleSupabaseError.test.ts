import assert from "node:assert/strict"
import { describe, it } from "node:test"
import { handleSupabaseError } from "./handleSupabaseError.ts"
import { supabaseMutationFeedback } from "./supabaseMutationFeedback.ts"
import {
  toUserFacingErrorMessage,
  USER_FACING_ERROR_MESSAGES,
} from "./userFacingError.ts"

describe("toUserFacingErrorMessage", () => {
  it("maps internal ALL_CAPS codes to friendly copy", () => {
    assert.equal(
      toUserFacingErrorMessage({ message: "FREE_PLAN_DAILY_POST_LIMIT" }),
      USER_FACING_ERROR_MESSAGES.FREE_PLAN_DAILY_POST_LIMIT
    )
    assert.equal(
      toUserFacingErrorMessage({ message: "FREE_PLAN_DAILY_TRADE_LIMIT" }),
      USER_FACING_ERROR_MESSAGES.FREE_PLAN_DAILY_TRADE_LIMIT
    )
    assert.equal(
      toUserFacingErrorMessage({ message: "FREE_PLAN_DAILY_CLIP_LIMIT" }),
      USER_FACING_ERROR_MESSAGES.FREE_PLAN_DAILY_CLIP_LIMIT
    )
  })

  it("preserves human-readable postgres sentences", () => {
    assert.equal(
      toUserFacingErrorMessage({
        code: "P0001",
        message: "You've reached the Free plan limit of 3 trades every 24 hours.",
      }),
      "You've reached the Free plan limit of 3 trades every 24 hours."
    )
  })

  it("uses hint when message is only a postgres code", () => {
    assert.equal(
      toUserFacingErrorMessage({
        code: "P0001",
        message: "P0001",
        hint: "You've reached the Free plan limit of 3 trades every 24 hours.",
      }),
      "You've reached the Free plan limit of 3 trades every 24 hours."
    )
  })

  it("maps rate_limit_exceeded payloads", () => {
    assert.equal(
      toUserFacingErrorMessage({ message: "rate_limit_exceeded:comment" }),
      USER_FACING_ERROR_MESSAGES.RATE_LIMIT_EXCEEDED
    )
  })

  it("returns generic text only when no usable message exists", () => {
    assert.equal(toUserFacingErrorMessage(null), USER_FACING_ERROR_MESSAGES.UNKNOWN_ERROR)
    assert.equal(toUserFacingErrorMessage({}), USER_FACING_ERROR_MESSAGES.UNKNOWN_ERROR)
    assert.equal(
      toUserFacingErrorMessage({ code: "P0001", message: "P0001" }),
      USER_FACING_ERROR_MESSAGES.UNKNOWN_ERROR
    )
  })

  it("maps free plan account limit codes", () => {
    assert.equal(
      toUserFacingErrorMessage({ message: "FREE_PLAN_ACCOUNT_LIMIT" }),
      USER_FACING_ERROR_MESSAGES.FREE_PLAN_ACCOUNT_LIMIT
    )
  })
})

describe("handleSupabaseError", () => {
  it("re-exports toUserFacingErrorMessage", () => {
    assert.equal(
      handleSupabaseError({ message: "FREE_PLAN_DAILY_POST_LIMIT" }),
      USER_FACING_ERROR_MESSAGES.FREE_PLAN_DAILY_POST_LIMIT
    )
  })
})

describe("supabaseMutationFeedback", () => {
  it("keeps caller title and friendly description for internal codes", () => {
    const feedback = supabaseMutationFeedback(
      { message: "FREE_PLAN_DAILY_POST_LIMIT" },
      "Post Failed"
    )
    assert.equal(feedback.title, "Post Failed")
    assert.equal(
      feedback.message,
      USER_FACING_ERROR_MESSAGES.FREE_PLAN_DAILY_POST_LIMIT
    )
    assert.equal(feedback.type, "error")
  })

  it("keeps caller title and database sentence for human-readable errors", () => {
    const feedback = supabaseMutationFeedback(
      {
        message:
          "You've reached the Free plan limit of 3 trades every 24 hours.",
      },
      "Save Failed"
    )
    assert.equal(feedback.title, "Save Failed")
    assert.equal(
      feedback.message,
      "You've reached the Free plan limit of 3 trades every 24 hours."
    )
  })
})
