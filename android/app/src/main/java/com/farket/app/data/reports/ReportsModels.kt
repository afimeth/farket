package com.farket.app.data.reports

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
internal data class ReportInsert(
    @SerialName("reporter_id") val reporterId: String,
    @SerialName("reported_profile_id") val reportedProfileId: String,
    val reason: String,
)

@Serializable
internal data class BlockInsert(
    @SerialName("blocker_id") val blockerId: String,
    @SerialName("blocked_id") val blockedId: String,
)

@Serializable
internal data class BlockedUserRow(
    @SerialName("profile_id") val profileId: String,
    val username: String? = null,
)

data class BlockedUser(
    val profileId: String,
    val username: String,
)
