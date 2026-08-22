package com.farket.app.data.auth

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.OtpType
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.OTP
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.functions.functions
import io.ktor.client.statement.bodyAsText
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

private const val REDIRECT_URL = "farket://login-callback"

@Serializable
private data class TestLoginRequest(val email: String, val code: String)

@Serializable
private data class TestLoginResponse(val token_hash: String, val email: String)

class EmailAuthRepository(
    private val supabase: SupabaseClient,
) : AuthRepository {

    override val sessionStatus: StateFlow<SessionStatus>
        get() = supabase.auth.sessionStatus

    override fun isSignedIn(): Boolean =
        sessionStatus.value is SessionStatus.Authenticated

    override suspend fun sendLoginLink(email: String): Result<Unit> = runCatching {
        supabase.auth.signInWith(OTP, redirectUrl = REDIRECT_URL) {
            this.email = email
        }
    }

    override suspend fun signInWithTestCode(email: String, code: String): Result<Unit> = runCatching {
        val trimmedEmail = email.trim()
        val response = supabase.functions.invoke(
            function = "test-login",
            body = TestLoginRequest(email = trimmedEmail, code = code.trim()),
        )
        val bodyText = response.bodyAsText()
        if (!response.status.value.let { it in 200..299 }) {
            error(Json.decodeFromString<Map<String, String>>(bodyText)["error"] ?: "Test girişi başarısız")
        }
        val parsed = Json.decodeFromString<TestLoginResponse>(bodyText)
        // admin.generateLink() bir "token_hash" (uzun hash) döner, kısa 6 haneli OTP kodu
        // değil. `token` parametresi GoTrue'nun /verify uç noktasına "token" alanı olarak
        // gidiyor ve bu alan kısa-kod akışı için; hash'i oraya koymak sahte bir
        // "otp_expired" hatasına yol açıyordu. Doğru alan `tokenHash`.
        supabase.auth.verifyEmailOtp(
            type = OtpType.Email.EMAIL,
            tokenHash = parsed.token_hash,
        )
    }

    override suspend fun signOut(): Result<Unit> = runCatching {
        supabase.auth.signOut()
    }
}
