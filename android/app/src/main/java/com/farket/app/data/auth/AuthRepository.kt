package com.farket.app.data.auth

import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.flow.StateFlow

/**
 * Giriş, e-postaya gönderilen bir bağlantıya dokunarak yapılır (link-tabanlı).
 * Supabase Cloud ücretsiz plan + varsayılan e-posta sağlayıcısı özel şablon
 * (dolayısıyla görünür bir 6 haneli kod) izin vermediği için, kod-girişi yerine
 * bu akış tercih edildi (bkz. DOCTOR.md 21 Ağustos). Bağlantıya dokununca
 * uygulama `farket://login-callback` deep-link'iyle açılır, MainActivity oturumu
 * tamamlar — bu repository yalnızca linki tetiklemekten sorumlu, doğrulamayı
 * SDK'nın deep-link işleyicisi yapar.
 */
interface AuthRepository {
    val sessionStatus: StateFlow<SessionStatus>

    /** Giriş bağlantısını e-posta adresine gönderir (hesap yoksa oluşturur). */
    suspend fun sendLoginLink(email: String): Result<Unit>

    /**
     * Beta test kısayolu: gerçek mail gönderilmeden, ekranda görünen sabit
     * test koduyla doğrudan oturum açar (bkz. DOCTOR.md 21 Ağustos —
     * Resend domain doğrulaması yapılana kadar geçerli).
     */
    suspend fun signInWithTestCode(email: String, code: String): Result<Unit>

    suspend fun signOut(): Result<Unit>
    fun isSignedIn(): Boolean
}
