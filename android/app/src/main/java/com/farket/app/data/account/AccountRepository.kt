package com.farket.app.data.account

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.rpc
import kotlinx.serialization.json.JsonElement

class AccountRepository(
    private val supabase: SupabaseClient,
) {
    suspend fun deleteAccount(): Result<Unit> = runCatching {
        supabase.postgrest.rpc("delete_account")
        Unit
    }

    suspend fun restoreAccount(): Result<Unit> = runCatching {
        supabase.postgrest.rpc("restore_account")
        Unit
    }

    suspend fun exportMyData(): Result<JsonElement> = runCatching {
        supabase.postgrest.rpc("export_my_data").decodeAs()
    }

    /** `status='deleted'` iken hesap 30 gün içinde `restore_account()` ile geri alınabilir. */
    suspend fun isAccountDeleted(): Boolean {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return false
        val row = supabase.postgrest.from("profiles")
            .select(columns = Columns.list("status", "deleted_at")) {
                filter { eq("id", userId) }
            }
            .decodeSingleOrNull<AccountStatusRow>()
        return row?.status == "deleted"
    }

    suspend fun signOut(): Result<Unit> = runCatching {
        supabase.auth.signOut()
    }

    /**
     * Gizlilik anahtarları. Şimdilik tek alan var (`share_quiz_progress`) ama tek kolon
     * için `profiles` tablosunu sorgulamak yerine RPC kullanılıyor: ileride eklenecek
     * anahtarlar aynı çağrıdan gelsin ve istemci profil şemasına bağlı kalmasın.
     */
    suspend fun getPrivacySettings(): Result<PrivacySettings> = runCatching {
        supabase.postgrest.rpc("get_my_privacy_settings").decodeAs()
    }

    /**
     * Quiz çözerken canlı ilerlemenin profil sahibine bildirilmesini aç/kapat.
     * Varsayılan açık — bu anahtar mevcut davranışı değiştirmez, yalnızca çıkış sunar.
     */
    suspend fun setShareQuizProgress(value: Boolean): Result<Unit> = runCatching {
        supabase.postgrest.rpc(
            function = "set_share_quiz_progress",
            parameters = ShareQuizProgressParams(value = value),
        )
        Unit
    }
}
