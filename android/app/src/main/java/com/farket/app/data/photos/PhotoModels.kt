package com.farket.app.data.photos

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class PhotoRow(
    val id: String,
    val position: Int,
    @SerialName("storage_path_thumb") val storagePathThumb: String,
    @SerialName("storage_path_full") val storagePathFull: String,
    @SerialName("moderation_status") val moderationStatus: String,
)

@Serializable
internal data class PhotoInsert(
    @SerialName("profile_id") val profileId: String,
    val position: Int,
    @SerialName("storage_path_thumb") val storagePathThumb: String,
    @SerialName("storage_path_full") val storagePathFull: String,
)

@Serializable
internal data class PositionUpdate(val position: Int)

@Serializable
internal data class SwapPositionsParams(
    @SerialName("photo_a_id") val photoAId: String,
    @SerialName("photo_b_id") val photoBId: String,
)
