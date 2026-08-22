package com.farket.app.data.messaging

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Gerçek sütun adları `participant_a`/`participant_b` (bkz. `messaging_functions.sql`
 * `send_message`: `insert into conversations (participant_a, participant_b, status)
 * values (v_sender_id, p_target_profile_id, ...)`) — yani `participant_a` her zaman
 * konuşmayı başlatan (requester), `participant_b` hedef taraf.
 */
@Serializable
data class ConversationRow(
    val id: String,
    @SerialName("participant_a") val requesterId: String,
    @SerialName("participant_b") val targetId: String,
    val status: String,
    @SerialName("created_at") val createdAt: String,
)

@Serializable
data class MessageRow(
    val id: String,
    @SerialName("conversation_id") val conversationId: String,
    @SerialName("sender_id") val senderId: String,
    val body: String,
    @SerialName("char_limit_applied") val charLimitApplied: Int? = null,
    @SerialName("created_at") val createdAt: String,
)

@Serializable
internal data class SendMessageParams(
    @SerialName("p_target_profile_id") val targetProfileId: String,
    @SerialName("p_body") val body: String,
)

@Serializable
data class SendMessageResult(
    @SerialName("conversation_id") val conversationId: String,
    val status: String,
    @SerialName("char_limit_applied") val charLimitApplied: Int? = null,
)

@Serializable
internal data class ConversationIdParams(
    @SerialName("p_conversation_id") val conversationId: String,
)

@Serializable
internal data class GetParticipantUsernameParams(
    @SerialName("p_conversation_id") val conversationId: String,
)

data class ConversationSummary(
    val conversation: ConversationRow,
    val otherUsername: String,
    val otherProfileId: String,
    val lastMessageBody: String?,
)
