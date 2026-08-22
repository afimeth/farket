package com.farket.app.data.quiz

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
internal data class StartQuizParams(
    @SerialName("p_target_profile_id") val targetProfileId: String,
)

@Serializable
data class QuizOption(
    val id: String,
    val body: String,
)

@Serializable
data class QuizQuestion(
    val position: Int,
    @SerialName("question_body") val questionBody: String,
    val options: List<QuizOption>,
)

@Serializable
data class StartQuizResult(
    @SerialName("attempt_id") val attemptId: String,
    val questions: List<QuizQuestion>,
)

@Serializable
internal data class SubmitAnswerParams(
    @SerialName("p_attempt_id") val attemptId: String,
    @SerialName("p_position") val position: Int,
    @SerialName("p_option_id") val optionId: String,
)

@Serializable
data class SubmitAnswerResult(
    val score: Int,
    @SerialName("checkpoint_passed") val checkpointPassed: Boolean? = null,
    @SerialName("unlocked_tier") val unlockedTier: Int? = null,
    val status: String? = null,
    // Checkpoint geçilince submit_answer artık reveal_identity'yi kendi içinde
    // çağırıp sonucu buraya gömüyor — ayrı bir round-trip'e gerek kalmıyor.
    val identity: Map<String, String>? = null,
)

@Serializable
internal data class AttemptIdParams(
    @SerialName("p_attempt_id") val attemptId: String,
)

@Serializable
data class CheckCheckpointResult(
    @SerialName("checkpoint_passed") val checkpointPassed: Boolean,
    val status: String,
    val score: Int,
)

@Serializable
data class FinishQuizResult(
    val score: Int,
    @SerialName("unlocked_tier") val unlockedTier: Int,
    val status: String,
)

/**
 * Günlük quiz hakkının koşul koşul dökümü (`get_quiz_allowance_breakdown`).
 *
 * Hak taban 3'ten başlar, kazanılan her koşul +1 ekler, tavan 7'dir. `allowance`
 * o gün için geçerli olan değer: gün içindeki ilk quiz denemesinde
 * `daily_quotas.quiz_allowance`'a sabitlenir ve o gün bir daha değişmez —
 * `lockedForToday` true iken kazanılan yeni bir koşul ancak yarın yansır.
 */
@Serializable
data class QuizAllowanceBreakdown(
    val allowance: Int,
    val used: Int,
    val remaining: Int,
    val base: Int,
    val cap: Int,
    @SerialName("locked_for_today") val lockedForToday: Boolean,
    val conditions: List<AllowanceCondition>,
)

@Serializable
data class AllowanceCondition(
    val key: String,
    val earned: Boolean,
    val bonus: Int,
    /** Yalnızca `quiz_health` koşulunda dolu: profilin quizinin genel çözülme oranı (%). */
    @SerialName("solve_rate") val solveRate: Int? = null,
    /** Aşağıdaki üçü yalnızca `profile_complete` koşulunda dolu. */
    @SerialName("photo_count") val photoCount: Int? = null,
    @SerialName("custom_question_count") val customQuestionCount: Int? = null,
    @SerialName("has_secret_card") val hasSecretCard: Boolean? = null,
)

/** Haftalık "erken ikinci şans" hakkının durumu (`get_early_retry_status`). */
@Serializable
data class EarlyRetryStatus(
    val available: Boolean,
    @SerialName("last_used_at") val lastUsedAt: String? = null,
    @SerialName("next_available_at") val nextAvailableAt: String? = null,
)

@Serializable
data class RedeemEarlyRetryResult(
    @SerialName("available_now") val availableNow: Boolean,
    @SerialName("retry_cost") val retryCost: Int,
    @SerialName("next_redeem_at") val nextRedeemAt: String,
)

@Serializable
internal data class TargetProfileParams(
    @SerialName("p_target_profile_id") val targetProfileId: String,
)

/**
 * İkinci deneme hakkı duran bir profil (`get_my_pending_retries`).
 *
 * Bu satırlar keşif destesinde GÖRÜNMEZ — `discover_profiles` bekleme süresi dolmamış
 * profilleri tamamen filtreliyor. Telafi mekaniğinin tek giriş noktası bu liste.
 */
@Serializable
data class PendingRetryRow(
    @SerialName("profile_id") val profileId: String,
    val username: String? = null,
    @SerialName("first_attempt_score") val firstAttemptScore: Int? = null,
    @SerialName("available_at") val availableAt: String,
    @SerialName("retry_cost") val retryCost: Int,
    @SerialName("released_early") val releasedEarly: Boolean = false,
) {
    /** Bekleme süresi doldu mu; dolduysa kullanıcı doğrudan ikinci denemeyi açabilir. */
    val isAvailableNow: Boolean
        get() = runCatching {
            java.time.OffsetDateTime.parse(availableAt).toInstant() <= java.time.Instant.now()
        }.getOrDefault(false)
}

/** `get_quiz_radar` satırı: kendi kalıp sorularının soru bazlı performansı. */
@Serializable
data class QuizRadarRow(
    @SerialName("template_id") val templateId: Int,
    val body: String,
    @SerialName("shown_count") val shownCount: Int,
    @SerialName("correct_rate") val correctRate: Int? = null,
    @SerialName("is_dead") val isDead: Boolean = false,
)
