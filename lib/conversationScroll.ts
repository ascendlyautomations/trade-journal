export type ScrollContainerOptions = {
  behavior?: ScrollBehavior
}

/** Jump or smoothly scroll a message list container to the newest message. */
export function scrollContainerToBottom(
  container: HTMLElement,
  options: ScrollContainerOptions = {}
) {
  const { behavior = "auto" } = options
  container.scrollTo({ top: container.scrollHeight, behavior })
}

export function isLastMessageInDom(
  lastMessageId: string | null,
  container: HTMLElement,
  lastMessage: { is_system?: boolean } | undefined
): boolean {
  if (!lastMessageId) return true
  if (lastMessage?.is_system) return true
  return Boolean(
    container.querySelector(
      `[data-dm-message-id="${CSS.escape(lastMessageId)}"]`
    )
  )
}
