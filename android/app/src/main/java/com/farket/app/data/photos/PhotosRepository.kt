package com.farket.app.data.photos

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.storage.storage
import java.util.UUID
import kotlin.time.Duration.Companion.minutes

const val MIN_PHOTOS = 5
const val MAX_PHOTOS = 7
private const val BUCKET = "profile-photos"

class PhotosRepository(
    private val supabase: SupabaseClient,
) {
    private fun requireUserId(): String =
        supabase.auth.currentUserOrNull()?.id ?: error("Oturum açılmamış")

    suspend fun listMyPhotos(): List<PhotoRow> =
        supabase.postgrest.from("photos")
            .select(columns = Columns.list("id", "position", "storage_path_thumb", "storage_path_full", "moderation_status")) {
                filter { eq("profile_id", requireUserId()) }
                order("position", Order.ASCENDING)
            }
            .decodeList()

    /**
     * `photos` görüntüleme kuralı sunucu tarafındaki `can_view_profile_photo_object()` ile
     * uygulanıyor (bkz. proje notları) — sahibi her zaman kendi fotoğrafını imzalayabilir,
     * istemci burada yalnızca isteği yapar.
     */
    suspend fun createSignedThumbUrl(path: String): String =
        supabase.storage.from(BUCKET).createSignedUrl(path, expiresIn = 30.minutes)

    suspend fun uploadPhoto(thumbBytes: ByteArray, fullBytes: ByteArray, extension: String) {
        val userId = requireUserId()
        val existing = listMyPhotos()
        require(existing.size < MAX_PHOTOS) { "En fazla $MAX_PHOTOS fotoğraf yükleyebilirsin" }

        val photoUuid = UUID.randomUUID()
        val thumbPath = "$userId/${photoUuid}_thumb.$extension"
        val fullPath = "$userId/${photoUuid}_full.$extension"

        val bucket = supabase.storage.from(BUCKET)
        bucket.upload(thumbPath, thumbBytes)
        bucket.upload(fullPath, fullBytes)

        val nextPosition = (existing.maxOfOrNull { it.position } ?: 0) + 1
        supabase.postgrest.from("photos").insert(
            PhotoInsert(
                profileId = userId,
                position = nextPosition,
                storagePathThumb = thumbPath,
                storagePathFull = fullPath,
            ),
        )
    }

    suspend fun deletePhoto(photo: PhotoRow) {
        supabase.storage.from(BUCKET).delete(photo.storagePathThumb, photo.storagePathFull)
        supabase.postgrest.from("photos").delete {
            filter { eq("id", photo.id) }
        }
    }

    /**
     * İki fotoğrafın `position`'ını takas eder (yukarı/aşağı taşıma). İki ayrı UPDATE isteği
     * `(profile_id, position)` unique kısıtına anında çarpardı; RPC tek transaction içinde
     * çalışıp kısıtın DEFERRED kontrolüne güveniyor (bkz. swap_photo_positions_rpc migration).
     */
    suspend fun swapPositions(a: PhotoRow, b: PhotoRow) {
        supabase.postgrest.rpc(
            function = "swap_photo_positions",
            parameters = SwapPositionsParams(photoAId = a.id, photoBId = b.id),
        )
    }
}
