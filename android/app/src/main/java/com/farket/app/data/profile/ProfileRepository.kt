package com.farket.app.data.profile

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import kotlinx.serialization.Serializable

/**
 * `profiles.status` sütununun bilinen değerleri. Backend `check` kısıtı bunu garanti eder;
 * ileride yeni bir status eklenirse burada da eklenmeli.
 */
enum class ProfileStatus {
    NO_PROFILE,
    DRAFT,
    PUBLISHED,
}

@Serializable
private data class ProfileStatusRow(val status: String)

class ProfileRepository(
    private val supabase: SupabaseClient,
) {
    /**
     * `profiles` satırı, telefon/OTP ile oturum açtıktan hemen sonra HENÜZ yoktur — istemcinin
     * profil kurulum sihirbazının ilk adımında kendisi insert etmesi gerekiyor (bkz. proje
     * notları, backend Görev 6). Bu yüzden her girişte satırın var olup olmadığı ve varsa
     * `status`'u kontrol edilip yönlendirme buna göre yapılıyor: satır yoksa ya da
     * `status='draft'` ise kurulum sihirbazına (kaldığı yerden), `status='published'` ise
     * doğrudan ana ekrana.
     */
    suspend fun getProfileStatus(): ProfileStatus {
        val userId = supabase.auth.currentUserOrNull()?.id ?: return ProfileStatus.NO_PROFILE
        val row = supabase.postgrest.from("profiles")
            .select(columns = Columns.list("status")) {
                filter { eq("id", userId) }
            }
            .decodeSingleOrNull<ProfileStatusRow>()
            ?: return ProfileStatus.NO_PROFILE

        return when (row.status) {
            "published" -> ProfileStatus.PUBLISHED
            else -> ProfileStatus.DRAFT
        }
    }
}
