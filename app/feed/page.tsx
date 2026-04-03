"use client"

import { useEffect, useState } from "react"
import { supabase } from "../../lib/supabaseClient"
import Navbar from "../components/Navbar"

export default function FeedPage() {
  const [posts, setPosts] = useState<any[]>([])
  const [user, setUser] = useState<any>(null)

  useEffect(() => {
    getUser()
    fetchPosts()
  }, [])

  async function getUser() {
    const { data } = await supabase.auth.getUser()
    setUser(data.user)
  }

  async function fetchPosts() {
    const { data } = await supabase
      .from("posts")
      .select("*")
      .order("created_at", { ascending: false })

    setPosts(data || [])
  }

  async function handleLike(postId: string) {
    await supabase.from("likes").insert({
      user_id: user.id,
      post_id: postId,
    })

    fetchPosts()
  }

  return (
    <>
      <Navbar />

      <div className="min-h-screen bg-gradient-to-br from-[#0f172a] via-[#1e3a8a] to-[#065f46] text-white">

        <div className="max-w-xl mx-auto p-6 space-y-6">

          {posts.map((post) => (
            <div
              key={post.id}
              className="bg-white/5 backdrop-blur-md border border-white/10 rounded-xl overflow-hidden"
            >

              {/* IMAGE */}
              {post.image_url && (
                <img
                  src={post.image_url}
                  className="w-full h-64 object-cover"
                />
              )}

              {/* CONTENT */}
              <div className="p-4 space-y-2">

                {/* PNL */}
                <div className="flex justify-between">
                  <span
                    className={
                      post.pnl >= 0
                        ? "text-emerald-400 font-bold"
                        : "text-red-400 font-bold"
                    }
                  >
                    ${post.pnl}
                  </span>

                  <span className="text-gray-400">
                    RR {post.rr}
                  </span>
                </div>

                {/* CAPTION */}
                <p className="text-sm text-gray-300">
                  {post.caption}
                </p>

                {/* ACTIONS */}
                <div className="flex gap-4 mt-2">

                  <button
                    onClick={() => handleLike(post.id)}
                    className="hover:text-emerald-400"
                  >
                    ❤️ Like
                  </button>

                  <button className="hover:text-blue-400">
                    💬 Comment
                  </button>

                </div>

              </div>
            </div>
          ))}

        </div>

      </div>
    </>
  )
}