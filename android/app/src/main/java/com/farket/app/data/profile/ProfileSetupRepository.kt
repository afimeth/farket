package com.farket.app.data.profile

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.storage.storage
import java.util.UUID
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withTimeout

/**
 * `profile_template_answers` istemciye tamamen kapalı (hiç GRANT yok, bkz. proje notları) —
 * daha önce cevaplanmış sorular sunucudan GERİ OKUNAMAZ. Bu yüzden bu sihirbaz, hangi
 * kalıp sorulara cevap verildiğini yalnızca bu oturum içinde ([ProfileSetupViewModel]'de)
 * takip eder; uygulama yeniden başlarsa bu sayaç sıfırlanır (RPC'ler idempotent/upsert
 * olduğundan tekrar cevaplamak veri bütünlüğünü bozmaz, yalnızca UI ilerleme göstergesi
 * baştan başlar).
 */
class ProfileSetupRepository(
    private val supabase: SupabaseClient,
) {
    private fun requireUserId(): String =
        supabase.auth.currentUserOrNull()?.id ?: error("Oturum açılmamış")

    suspend fun listCities(): List<CityRow> =
        supabase.postgrest.from("cities")
            .select(columns = Columns.list("id", "name")) {
                filter { eq("is_active", true) }
                order("name", Order.ASCENDING)
            }
            .decodeList()

    /**
     * `upsert` — sihirbazın adım ilerlemesi yalnızca bellekte tutuluyor (bkz. sınıf yorumu),
     * yani süreç yeniden başlarsa kullanıcı 1. adımdan tekrar geçer. Profil satırı zaten
     * oluşturulmuşsa düz `insert` `profiles_pkey` çakışmasıyla patlar; `upsert` bunu güncelleme
     * olarak ele alır.
     */
    suspend fun createBasicProfile(displayName: String, birthDate: String, sex: String, cityId: Int) {
        supabase.postgrest.from("profiles").upsert(
            ProfileInsert(
                id = requireUserId(),
                displayName = displayName,
                birthDate = birthDate,
                sex = sex,
                cityId = cityId,
            ),
        )
    }

    suspend fun attestAge() {
        val nowIso = java.time.Instant.now().toString()
        supabase.postgrest.from("profiles").update(AgeAttestationUpdate(ageAttestedAt = nowIso)) {
            filter { eq("id", requireUserId()) }
        }
    }

    suspend fun setUsername(username: String) {
        supabase.postgrest.from("profiles").update(UsernameUpdate(username = username)) {
            filter { eq("id", requireUserId()) }
        }
    }

    suspend fun createIdentityCard(
        showName: Boolean,
        showAge: Boolean,
        showOccupation: Boolean,
        showCity: Boolean,
        showIntent: Boolean,
        occupation: String?,
        intent: String,
    ) {
        supabase.postgrest.from("identity_card").upsert(
            IdentityCardInsert(
                profileId = requireUserId(),
                showName = showName,
                showAge = showAge,
                showOccupation = showOccupation,
                showCity = showCity,
                showIntent = showIntent,
                occupation = occupation,
                intent = intent,
            ),
        )
    }

    suspend fun listIdentityAttributes(): List<IdentityAttributeRow> =
        supabase.postgrest.from("profile_identity_attributes")
            .select(
                columns = Columns.list(
                    "attribute_type", "value_text", "value_numeric", "is_shown_on_reveal", "is_quiz_eligible",
                ),
            ) {
                filter { eq("profile_id", requireUserId()) }
            }
            .decodeList()

    /** `unique(profile_id, attribute_type)` upsert hedefi — mevcut bir alanı düzenlemek de aynı çağrıyla yapılır. */
    suspend fun submitIdentityAttributes(attributes: List<IdentityAttributeDraft>) {
        val userId = requireUserId()
        attributes.forEach { attr ->
            supabase.postgrest.from("profile_identity_attributes").upsert(
                IdentityAttributeUpsert(
                    profileId = userId,
                    attributeType = attr.attributeType,
                    valueText = attr.valueText,
                    valueNumeric = attr.valueNumeric,
                    isShownOnReveal = attr.isShownOnReveal,
                    isQuizEligible = attr.isQuizEligible,
                ),
            ) {
                onConflict = "profile_id,attribute_type"
            }
        }
    }

    suspend fun hasQuizEligibleAttribute(): Boolean =
        supabase.postgrest.from("profile_identity_attributes")
            .select(columns = Columns.list("attribute_type")) {
                filter {
                    eq("profile_id", requireUserId())
                    eq("is_quiz_eligible", true)
                }
            }
            .decodeList<QuizEligibleAttributeRow>()
            .isNotEmpty()

    /**
     * Bir fotoğrafı hem Storage'a (thumb+full) hem `photos` tablosuna yazar.
     *
     * `withTimeout` — emülatörde bulunan gerçek bir hata: Storage sunucusu her iki yüklemeyi de
     * (thumb+full) 200 ile onaylasa bile istemci tarafı (Ktor/OkHttp) bazen yanıtı hiç
     * tamamlamadan sonsuza kadar askıda kalabiliyor (`photos` insert isteği asla gönderilmiyordu,
     * PostgREST loglarında hiç görünmüyordu). Kalıcı çözüm supabase-kt/OkHttp tarafında ayrı bir
     * araştırma gerektiriyor; burada en az kullanıcının sonsuza kadar dönen bir spinner'da
     * kalmaması için bir zaman aşımı ekleniyor.
     */
    suspend fun uploadPhoto(position: Int, thumbBytes: ByteArray, fullBytes: ByteArray, extension: String) {
        val userId = requireUserId()
        val photoUuid = UUID.randomUUID()
        val thumbPath = "$userId/${photoUuid}_thumb.$extension"
        val fullPath = "$userId/${photoUuid}_full.$extension"

        try {
            withTimeout(20_000) {
                val bucket = supabase.storage.from("profile-photos")
                bucket.upload(thumbPath, thumbBytes)
                bucket.upload(fullPath, fullBytes)

                supabase.postgrest.from("photos").insert(
                    PhotoInsert(
                        profileId = userId,
                        position = position,
                        storagePathThumb = thumbPath,
                        storagePathFull = fullPath,
                    ),
                )
            }
        } catch (e: TimeoutCancellationException) {
            throw Exception("Fotoğraf yüklenemedi (zaman aşımı) — tekrar dene", e)
        }
    }

    suspend fun listTemplates(act: Int, hardOnly: Boolean): List<QuestionTemplateRow> =
        supabase.postgrest.from("question_templates")
            .select(columns = Columns.list("id", "body", "default_difficulty", "taxonomy_id")) {
                filter {
                    eq("act", act)
                    eq("is_active", true)
                    if (hardOnly) {
                        eq("default_difficulty", "hard")
                    }
                }
                order("id", Order.ASCENDING)
            }
            .decodeList()

    suspend fun listTemplateOptions(templateId: Int): List<TemplateOptionRow> =
        supabase.postgrest.from("template_options")
            .select(columns = Columns.list("id", "body")) {
                filter { eq("template_id", templateId) }
                order("position", Order.ASCENDING)
            }
            .decodeList()

    suspend fun getTaxonomyItems(taxonomyId: Int): List<TaxonomyItemRow> =
        supabase.postgrest.rpc(
            function = "get_taxonomy_items",
            parameters = GetTaxonomyItemsParams(taxonomyId = taxonomyId),
        ).decodeAs()

    suspend fun setTemplateAnswer(templateId: Int, selectedOptionId: Int?, selectedItemId: Int?) {
        supabase.postgrest.rpc(
            function = "set_template_answer",
            parameters = SetTemplateAnswerParams(
                templateId = templateId,
                selectedOptionId = selectedOptionId,
                selectedItemId = selectedItemId,
            ),
        )
    }

    suspend fun removeTemplateAnswer(templateId: Int) {
        supabase.postgrest.rpc(
            function = "remove_template_answer",
            parameters = RemoveTemplateAnswerParams(templateId = templateId),
        )
    }

    /** Serbest soru + şıkları + doğru şık işaretlemesini tek adımda yapar. */
    suspend fun createCustomQuestion(body: String, optionBodies: List<String>, correctOptionIndex: Int): Unit {
        val userId = requireUserId()
        val questionId = supabase.postgrest.from("custom_questions")
            .insert(CustomQuestionInsert(profileId = userId, body = body)) {
                select(columns = Columns.list("id"))
            }
            .decodeSingle<IdRow>()
            .id

        val optionIds = optionBodies.mapIndexed { index, optionBody ->
            supabase.postgrest.from("custom_options")
                .insert(CustomOptionInsert(questionId = questionId, body = optionBody, position = index + 1)) {
                    select(columns = Columns.list("id"))
                }
                .decodeSingle<IdRow>()
                .id
        }

        supabase.postgrest.from("custom_questions")
            .update(CorrectOptionUpdate(correctOptionId = optionIds[correctOptionIndex])) {
                filter { eq("id", questionId) }
            }
    }

    suspend fun publishProfile(): Result<PublishProfileResult> = runCatching {
        supabase.postgrest.rpc(function = "publish_profile").decodeAs()
    }

    /**
     * Sihirbaz yeniden açıldığında kaldığı adımı bulmak için sunucudaki mevcut ilerlemeyi okur.
     * `profiles`/`identity_card`/`photos`/`custom_questions` zaten sahibine SELECT ile açık;
     * `profile_template_answers` ise hiç GRANT'lı değil (bkz. grants.sql), o yüzden onun için
     * ayrıca eklenen `get_my_template_progress()` RPC'si kullanılıyor.
     */
    suspend fun getDraftProgress(): DraftProgress {
        val userId = requireUserId()

        val profile = supabase.postgrest.from("profiles")
            .select(columns = Columns.list("display_name", "age_attested_at", "username")) {
                filter { eq("id", userId) }
            }
            .decodeSingleOrNull<DraftProfileRow>()

        val hasIdentityCard = supabase.postgrest.from("identity_card")
            .select(columns = Columns.list("profile_id")) {
                filter { eq("profile_id", userId) }
            }
            .decodeList<IdentityCardProfileIdRow>()
            .isNotEmpty()

        val photoCount = supabase.postgrest.from("photos")
            .select(columns = Columns.list("id")) {
                filter { eq("profile_id", userId) }
            }
            .decodeList<IdRow>()
            .size

        val hasCustomQuestion = supabase.postgrest.from("custom_questions")
            .select(columns = Columns.list("id")) {
                filter { eq("profile_id", userId) }
            }
            .decodeList<IdRow>()
            .isNotEmpty()

        val hasQuizEligibleAttribute = hasQuizEligibleAttribute()

        val templateProgress = supabase.postgrest.rpc(function = "get_my_template_progress")
            .decodeList<TemplateProgressRow>()

        return DraftProgress(
            hasBasicInfo = profile?.displayName != null,
            ageAttested = profile?.ageAttestedAt != null,
            hasUsername = profile?.username != null,
            hasIdentityCard = hasIdentityCard,
            hasQuizEligibleAttribute = hasQuizEligibleAttribute,
            photoCount = photoCount,
            act1Answered = templateProgress.filter { it.difficulty != "hard" }.map { it.templateId }.toSet(),
            act2HardAnswered = templateProgress.filter { it.difficulty == "hard" }.map { it.templateId }.toSet(),
            hasCustomQuestion = hasCustomQuestion,
        )
    }
}

data class DraftProgress(
    val hasBasicInfo: Boolean,
    val ageAttested: Boolean,
    val hasUsername: Boolean,
    val hasIdentityCard: Boolean,
    val hasQuizEligibleAttribute: Boolean,
    val photoCount: Int,
    val act1Answered: Set<Int>,
    val act2HardAnswered: Set<Int>,
    val hasCustomQuestion: Boolean,
)
