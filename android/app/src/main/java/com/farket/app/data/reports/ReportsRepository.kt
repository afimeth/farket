package com.farket.app.data.reports

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc

/** Şikayet/engelleme için RPC yok — RLS "yalnızca kendi adına" kuralını doğrudan insert/delete üzerinde uyguluyor. */
class ReportsRepository(
    private val supabase: SupabaseClient,
) {
    private fun requireUserId(): String =
        supabase.auth.currentUserOrNull()?.id ?: error("Oturum açılmamış")

    suspend fun report(targetProfileId: String, reason: String): Result<Unit> = runCatching {
        supabase.postgrest.from("reports").insert(
            ReportInsert(reporterId = requireUserId(), reportedProfileId = targetProfileId, reason = reason),
        )
        Unit
    }

    /** Engelleme, aralarındaki açık konuşmayı backend'de bir trigger ile otomatik kapatır. */
    suspend fun block(targetProfileId: String): Result<Unit> = runCatching {
        supabase.postgrest.from("blocks").insert(
            BlockInsert(blockerId = requireUserId(), blockedId = targetProfileId),
        )
        Unit
    }

    suspend fun unblock(targetProfileId: String): Result<Unit> = runCatching {
        val userId = requireUserId()
        supabase.postgrest.from("blocks").delete {
            filter {
                eq("blocker_id", userId)
                eq("blocked_id", targetProfileId)
            }
        }
        Unit
    }

    /**
     * `profiles` tablosunda tek select politikası "yalnızca kendi profilin" olduğu için
     * (bkz. rls_policies.sql), engellenenlerin adı bir RPC üzerinden okunuyor — aynı desen
     * `get_conversation_participant_username` ile (bkz. get_blocked_users_rpc migration).
     */
    suspend fun listBlocked(): List<BlockedUser> =
        supabase.postgrest.rpc(function = "get_blocked_users")
            .decodeList<BlockedUserRow>()
            .map { BlockedUser(profileId = it.profileId, username = it.username ?: "?") }
}
