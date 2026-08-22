package com.farket.app.data.discovery

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.storage.storage
import kotlin.time.Duration.Companion.minutes

private const val BUCKET = "profile-photos"
private const val DEFAULT_LIMIT = 20

class DiscoveryRepository(
    private val supabase: SupabaseClient,
) {

    /**
     * Günlük kota (200) aşımında backend `'Günlük keşif çağrı kotan doldu'` hatasını fırlatır —
     * bu, `Result.failure`'ın `message`'ında aynen gelir; UI katmanı daha okunaklı bir mesaja
     * çevirebilir.
     */
    suspend fun discoverProfiles(limit: Int = DEFAULT_LIMIT): Result<List<DiscoverProfileRow>> = runCatching {
        supabase.postgrest.rpc(
            function = "discover_profiles",
            parameters = DiscoverProfilesParams(limit = limit),
        ).decodeAs()
    }

    suspend fun getPublicProfile(profileId: String): Result<PublicProfileResult> = runCatching {
        supabase.postgrest.rpc(
            function = "get_public_profile",
            parameters = GetPublicProfileParams(profileId = profileId),
        ).decodeAs()
    }

    suspend fun skipProfile(targetProfileId: String): Result<Unit> = runCatching {
        supabase.postgrest.rpc(
            function = "skip_profile",
            parameters = TargetProfileParams(targetProfileId = targetProfileId),
        )
        Unit
    }

    suspend fun createSignedUrl(path: String): String =
        supabase.storage.from(BUCKET).createSignedUrl(path, expiresIn = 30.minutes)
}
