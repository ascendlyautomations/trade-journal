import { supabase } from "@/lib/supabaseClient"

export async function createUserRoom(userId: string, username: string) {
  // Generate slug (simple version)
  const slug = `${username}-${Date.now()}`

  const { data, error } = await supabase
    .from("rooms")
    .insert({
      name: `${username}'s Room`,
      description: "Personal Trade Room",
      owner_user_id: userId,
      slug,
    })
    .select()
    .single()

  if (error) {
    console.error("Create room error:", error)
    throw error
  }

  const { error: sectionsError } = await supabase.from("room_sections").insert([
    { room_id: data.id, name: "general", position: 1 },
    { room_id: data.id, name: "trades", position: 2 },
  ])

  if (sectionsError) {
    console.error("Create room_sections error:", sectionsError)
    throw sectionsError
  }

  const { error: memberError } = await supabase.from("room_members").insert({
    room_id: data.id,
    user_id: userId,
  })

  if (memberError) {
    console.error("Create room_members error:", memberError)
    throw memberError
  }

  return data
}
