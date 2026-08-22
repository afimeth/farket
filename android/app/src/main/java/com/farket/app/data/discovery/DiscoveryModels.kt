package com.farket.app.data.discovery

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class DiscoverProfileRow(
    val id: String,
    val username: String,
    @SerialName("cover_photo_thumb") val coverPhotoThumb: String? = null,
    @SerialName("photo_count") val photoCount: Int = 0,
    val photos: List<String> = emptyList(),
    @SerialName("solve_rate") val solveRate: Int? = null,
    @SerialName("is_bot") val isBot: Boolean = false,
)

@Serializable
data class PublicPhotoRow(
    val id: String,
    val position: Int,
    @SerialName("storage_path_thumb") val storagePathThumb: String,
    @SerialName("storage_path_full") val storagePathFull: String,
)

@Serializable
data class PublicProfileResult(
    val id: String,
    val username: String,
    val city: String? = null,
    val photos: List<PublicPhotoRow> = emptyList(),
    @SerialName("solve_rate") val solveRate: Int? = null,
)

@Serializable
internal data class DiscoverProfilesParams(
    @SerialName("p_limit") val limit: Int,
)

@Serializable
internal data class TargetProfileParams(
    @SerialName("p_target_profile_id") val targetProfileId: String,
)

@Serializable
internal data class GetPublicProfileParams(
    @SerialName("p_profile_id") val profileId: String,
)
