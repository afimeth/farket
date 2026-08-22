package com.farket.app.data.identity

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc

class IdentityRepository(
    private val supabase: SupabaseClient,
) {
    /**
     * Checkpoint geçilmeden çağrılırsa backend hata döner (bkz. proje notları).
     * RPC dönüşü ham bir jsonb map'i (attribute_type -> value) — sabit alanlı
     * bir data class yerine doğrudan Map olarak decode edilip sarmalanıyor.
     */
    suspend fun revealIdentity(attemptId: String): Result<IdentityRevealResult> = runCatching {
        val map: Map<String, String> = supabase.postgrest.rpc(
            function = "reveal_identity",
            parameters = RevealIdentityParams(attemptId = attemptId),
        ).decodeAs()
        IdentityRevealResult(attributes = map)
    }
}
