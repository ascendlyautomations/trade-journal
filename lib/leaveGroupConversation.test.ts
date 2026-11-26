import { describe, expect, it, vi } from "vitest"
import { leaveGroupConversation } from "./leaveGroupConversation"

describe("leaveGroupConversation", () => {
  it("maps rpc left status", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { status: "left" }, error: null })
    const supabase = { rpc } as never
    const result = await leaveGroupConversation(supabase, "convo-1")
    expect(result.error).toBeNull()
    expect(result.status).toBe("left")
    expect(rpc).toHaveBeenCalledWith("rpc_v1_leave_group_conversation", {
      p_conversation_id: "convo-1",
    })
  })

  it("maps rpc already_left status", async () => {
    const rpc = vi.fn().mockResolvedValue({ data: { status: "already_left" }, error: null })
    const supabase = { rpc } as never
    const result = await leaveGroupConversation(supabase, "convo-1")
    expect(result.status).toBe("already_left")
  })
})