package com.farket.app.data.notifications

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

/**
 * İlk 4 tip (quiz_started, identity_revealed, quiz_passed, perfect_score) ANONİM döner:
 * actorUsername her zaman null, payload.count aynı gün gruplanan olay sayısını taşır.
 * Son 2 tip (message_request, request_accepted) kimlik zaten açık olduğu için actorUsername dolu gelir.
 */
@Serializable
data class NotificationRow(
    val id: String,
    val type: String,
    val payload: JsonElement,
    @SerialName("actor_username") val actorUsername: String? = null,
    @SerialName("conversation_id") val conversationId: String? = null,
    @SerialName("progress_current") val progressCurrent: Int? = null,
    @SerialName("progress_score") val progressScore: Int? = null,
    @SerialName("is_near_miss") val isNearMiss: Boolean = false,
    @SerialName("read_at") val readAt: String? = null,
    @SerialName("created_at") val createdAt: String,
)

@Serializable
internal data class GetMyNotificationsParams(
    @SerialName("p_limit") val limit: Int = 30,
)

@Serializable
internal data class MarkNotificationReadParams(
    @SerialName("p_notification_id") val notificationId: String,
)

object NotificationType {
    const val QUIZ_STARTED = "quiz_started"
    const val IDENTITY_REVEALED = "identity_revealed"
    const val QUIZ_PASSED = "quiz_passed"
    const val PERFECT_SCORE = "perfect_score"
    const val MESSAGE_REQUEST = "message_request"
    const val REQUEST_ACCEPTED = "request_accepted"
    const val QUIZ_PROGRESS = "quiz_progress"
    const val NEAR_MISS = "near_miss"
    const val REQUEST_EXPIRED = "request_expired"
    const val WEEKLY_DIGEST = "weekly_digest"

    /** message_request/request_accepted: konuşma ekranına yönlendirilebilir, kimlik açık. */
    val CONVERSATION_LINKED = setOf(MESSAGE_REQUEST, REQUEST_ACCEPTED)
}
