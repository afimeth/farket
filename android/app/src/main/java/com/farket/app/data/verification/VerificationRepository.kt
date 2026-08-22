package com.farket.app.data.verification

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.storage.storage
import java.util.UUID
import kotlinx.serialization.Serializable

enum class VerificationStatus { NONE, PENDING, VERIFIED, REJECTED }

@Serializable
private data class RequestVerificationParams(@kotlinx.serialization.SerialName("p_selfie_path") val selfiePath: String)

/**
 * `request_verification` RPC'si ve `verification-selfies` bucket'ı backend'de zaten
 * kuruluydu (bkz. proje notları) ama bunu çağıran bir istemci hiç yazılmamıştı —
 * kullanıcı için doğrulama talep etmenin fiilen bir yolu yoktu.
 */
class VerificationRepository(
    private val supabase: SupabaseClient,
) {
    private fun requireUserId(): String =
        supabase.auth.currentUserOrNull()?.id ?: error("Oturum açılmamış")

    suspend fun getStatus(): VerificationStatus {
        val status = supabase.postgrest.rpc(function = "get_my_verification_status").decodeAs<String>()
        return when (status) {
            "verified" -> VerificationStatus.VERIFIED
            "pending" -> VerificationStatus.PENDING
            "rejected" -> VerificationStatus.REJECTED
            else -> VerificationStatus.NONE
        }
    }

    suspend fun submit(selfieBytes: ByteArray, extension: String): Result<Unit> = runCatching {
        val userId = requireUserId()
        val path = "$userId/${UUID.randomUUID()}.$extension"
        supabase.storage.from("verification-selfies").upload(path, selfieBytes)
        supabase.postgrest.rpc(
            function = "request_verification",
            parameters = RequestVerificationParams(selfiePath = path),
        )
        Unit
    }
}
