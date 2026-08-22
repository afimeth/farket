package com.farket.app.data.account

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
internal data class AccountStatusRow(
    val status: String,
    @SerialName("deleted_at") val deletedAt: String? = null,
)

@Serializable
data class PrivacySettings(
    @SerialName("share_quiz_progress") val shareQuizProgress: Boolean = true,
)

@Serializable
internal data class ShareQuizProgressParams(
    @SerialName("p_value") val value: Boolean,
)
