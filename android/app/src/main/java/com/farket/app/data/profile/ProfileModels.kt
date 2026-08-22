package com.farket.app.data.profile

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CityRow(
    val id: Int,
    val name: String,
)

@Serializable
internal data class ProfileInsert(
    val id: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("birth_date") val birthDate: String,
    val sex: String,
    @SerialName("city_id") val cityId: Int,
)

@Serializable
internal data class UsernameUpdate(val username: String)

@Serializable
internal data class AgeAttestationUpdate(@SerialName("age_attested_at") val ageAttestedAt: String)

@Serializable
internal data class IdentityCardInsert(
    @SerialName("profile_id") val profileId: String,
    @SerialName("show_name") val showName: Boolean,
    @SerialName("show_age") val showAge: Boolean,
    @SerialName("show_occupation") val showOccupation: Boolean,
    @SerialName("show_city") val showCity: Boolean,
    @SerialName("show_intent") val showIntent: Boolean,
    val occupation: String?,
    val intent: String,
)

@Serializable
internal data class PhotoInsert(
    @SerialName("profile_id") val profileId: String,
    val position: Int,
    @SerialName("storage_path_thumb") val storagePathThumb: String,
    @SerialName("storage_path_full") val storagePathFull: String,
)

@Serializable
data class QuestionTemplateRow(
    val id: Int,
    val body: String,
    @SerialName("default_difficulty") val defaultDifficulty: String? = null,
    @SerialName("taxonomy_id") val taxonomyId: Int? = null,
)

@Serializable
data class TemplateOptionRow(
    val id: Int,
    val body: String,
)

@Serializable
data class TaxonomyItemRow(
    val id: Int,
    val label: String,
)

@Serializable
internal data class SetTemplateAnswerParams(
    @SerialName("p_template_id") val templateId: Int,
    @SerialName("p_selected_option_id") val selectedOptionId: Int? = null,
    @SerialName("p_selected_item_id") val selectedItemId: Int? = null,
)

@Serializable
internal data class RemoveTemplateAnswerParams(
    @SerialName("p_template_id") val templateId: Int,
)

@Serializable
internal data class GetTaxonomyItemsParams(
    @SerialName("p_taxonomy_id") val taxonomyId: Int,
)

@Serializable
internal data class CustomQuestionInsert(
    @SerialName("profile_id") val profileId: String,
    val body: String,
)

@Serializable
internal data class IdRow(val id: String)

@Serializable
internal data class CustomOptionInsert(
    @SerialName("question_id") val questionId: String,
    val body: String,
    val position: Int,
)

@Serializable
internal data class CorrectOptionUpdate(
    @SerialName("correct_option_id") val correctOptionId: String,
)

@Serializable
data class PublishProfileResult(
    val status: String,
)

/** get_my_template_progress() satırı — kullanıcının daha önce cevapladığı kalıp soru id'si + zorluk. */
@Serializable
internal data class TemplateProgressRow(
    @SerialName("template_id") val templateId: Int,
    val difficulty: String,
)

/**
 * Sihirbazın kaldığı yeri belirlemek için `profiles`/`identity_card`/`photos`/`custom_questions`
 * satırlarından okunan minimal alanlar (hepsi authenticated'e zaten SELECT ile açık).
 */
@Serializable
internal data class DraftProfileRow(
    @SerialName("display_name") val displayName: String? = null,
    @SerialName("age_attested_at") val ageAttestedAt: String? = null,
    val username: String? = null,
)

@Serializable
internal data class IdentityCardProfileIdRow(
    @SerialName("profile_id") val profileId: String,
)

/** `profile_identity_attributes` satırı — hem sihirbaz hem ayarlar ekranı bunu okuyup yazar. */
@Serializable
data class IdentityAttributeRow(
    @SerialName("attribute_type") val attributeType: String,
    @SerialName("value_text") val valueText: String? = null,
    @SerialName("value_numeric") val valueNumeric: Double? = null,
    @SerialName("is_shown_on_reveal") val isShownOnReveal: Boolean = false,
    @SerialName("is_quiz_eligible") val isQuizEligible: Boolean = false,
)

@Serializable
internal data class IdentityAttributeUpsert(
    @SerialName("profile_id") val profileId: String,
    @SerialName("attribute_type") val attributeType: String,
    @SerialName("value_text") val valueText: String? = null,
    @SerialName("value_numeric") val valueNumeric: Double? = null,
    @SerialName("is_shown_on_reveal") val isShownOnReveal: Boolean = false,
    @SerialName("is_quiz_eligible") val isQuizEligible: Boolean = false,
)

@Serializable
internal data class QuizEligibleAttributeRow(
    @SerialName("attribute_type") val attributeType: String,
)

/** UI'dan repository'ye taşınan, henüz doğrulanmamış tek bir künye alanı taslağı. */
data class IdentityAttributeDraft(
    val attributeType: String,
    val valueText: String? = null,
    val valueNumeric: Double? = null,
    val isShownOnReveal: Boolean,
    val isQuizEligible: Boolean,
)
