/** PostgREST embeds for one-level parent reply references. */

export const ROOM_MESSAGE_PARENT_EMBED = `
  parent:room_messages!room_messages_parent_message_id_fkey (
    id,
    user_id,
    content,
    type,
    image_url,
    profiles (
      username,
      avatar_url
    )
  )
`

export const DM_MESSAGE_PARENT_EMBED = `
  parent:messages!messages_parent_message_id_fkey (
    id,
    sender_id,
    content,
    type,
    image_url,
    deleted_for_everyone,
    profiles!sender_id (
      username,
      avatar_url
    )
  )
`
