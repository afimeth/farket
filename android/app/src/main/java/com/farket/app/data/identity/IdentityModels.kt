package com.farket.app.data.identity

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
internal data class RevealIdentityParams(
    @SerialName("p_attempt_id") val attemptId: String,
)

/**
 * reveal_identity artık sabit alanlar yerine profile_identity_attributes'taki
 * is_shown_on_reveal=true satırlarından dinamik bir jsonb_object_agg döndürüyor
 * (attribute_type -> value). Bu yüzden client tarafı da sabit data class yerine
 * bir Map ile deserialize ediyor; hangi alanların geleceği profilden profile değişir.
 */
@Serializable
data class IdentityRevealResult(
    val attributes: Map<String, String> = emptyMap(),
) {
    val hasAnyField: Boolean
        get() = attributes.isNotEmpty()
}

/** attribute_type -> kullanıcıya gösterilecek Türkçe etiket. */
val IDENTITY_ATTRIBUTE_LABELS: Map<String, String> = mapOf(
    "name" to "İsim",
    "age" to "Yaş",
    "school" to "Okul",
    "job" to "İş",
    "height_cm" to "Boy",
    "weight_kg" to "Kilo",
    "city" to "Şehir",
    "intent" to "Aradığı",
    "hometown" to "Memleket",
)
