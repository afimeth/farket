package com.farket.app.data.messaging

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc
import io.github.jan.supabase.postgrest.query.filter.FilterOperator
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.decodeRecord
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.realtime
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

class MessagingRepository(
    private val supabase: SupabaseClient,
) {
    private fun requireUserId(): String =
        supabase.auth.currentUserOrNull()?.id ?: error("Oturum açılmamış")

    suspend fun listMyConversations(): List<ConversationSummary> {
        val userId = requireUserId()
        val conversations = supabase.postgrest.from("conversations")
            .select {
                filter {
                    or {
                        eq("participant_a", userId)
                        eq("participant_b", userId)
                    }
                }
                order("created_at", Order.DESCENDING)
            }
            .decodeList<ConversationRow>()

        return conversations.map { conversation ->
            val otherId = if (conversation.requesterId == userId) conversation.targetId else conversation.requesterId
            val otherUsername = getUsername(conversation.id)

            val lastMessage = supabase.postgrest.from("messages")
                .select(columns = Columns.list("id", "conversation_id", "sender_id", "body", "char_limit_applied", "created_at")) {
                    filter { eq("conversation_id", conversation.id) }
                    order("created_at", Order.DESCENDING)
                    limit(1)
                }
                .decodeSingleOrNull<MessageRow>()

            ConversationSummary(
                conversation = conversation,
                otherUsername = otherUsername,
                otherProfileId = otherId,
                lastMessageBody = lastMessage?.body,
            )
        }
    }

    suspend fun getConversation(conversationId: String): ConversationRow =
        supabase.postgrest.from("conversations")
            .select {
                filter { eq("id", conversationId) }
            }
            .decodeSingle()

    /**
     * `p_conversation_id` alır, rastgele bir `profile_id` almaz — çağıranın gerçekten o
     * konuşmanın bir tarafı olduğunu backend'de doğrulayıp karşı tarafın username'ini döndürür
     * (bkz. `get_conversation_participant_username` migration'ı; `profiles` tablosu RLS ile
     * doğrudan sorgulanamıyor, bu yüzden `profiles_select_own` bunu sessizce engelliyordu).
     */
    suspend fun getUsername(conversationId: String): String =
        runCatching {
            supabase.postgrest.rpc(
                function = "get_conversation_participant_username",
                parameters = GetParticipantUsernameParams(conversationId = conversationId),
            ).decodeAs<String>()
        }.getOrDefault("?")

    suspend fun listMessages(conversationId: String): List<MessageRow> =
        supabase.postgrest.from("messages")
            .select {
                filter { eq("conversation_id", conversationId) }
                order("created_at", Order.ASCENDING)
            }
            .decodeList()

    /**
     * İlk mesaj için `unlocked_tier > 0` şart, `status='pending'` iken gönderen ikinci mesajı
     * gönderemez — backend bunu reddeder, hata mesajı olduğu gibi çağırana taşınır
     * (bkz. proje notları).
     */
    suspend fun sendMessage(targetProfileId: String, body: String): Result<SendMessageResult> = runCatching {
        supabase.postgrest.rpc(
            function = "send_message",
            parameters = SendMessageParams(targetProfileId = targetProfileId, body = body),
        ).decodeAs()
    }

    suspend fun acceptConversation(conversationId: String): Result<Unit> = runCatching {
        supabase.postgrest.rpc(
            function = "accept_conversation",
            parameters = ConversationIdParams(conversationId = conversationId),
        )
        Unit
    }

    suspend fun declineConversation(conversationId: String): Result<Unit> = runCatching {
        supabase.postgrest.rpc(
            function = "decline_conversation",
            parameters = ConversationIdParams(conversationId = conversationId),
        )
        Unit
    }

    /** Polling yerine: `messages` tablosuna yeni satır geldiğinde canlı bildirir. */
    fun newMessagesFlow(conversationId: String): Flow<MessageRow> {
        val channel = supabase.realtime.channel("conversation-$conversationId")
        return channel.postgresChangeFlow<PostgresAction.Insert>(schema = "public") {
            table = "messages"
            filter("conversation_id", FilterOperator.EQ, conversationId)
        }.map { it.decodeRecord<MessageRow>() }
    }

    suspend fun subscribeToChannel(conversationId: String) {
        supabase.realtime.channel("conversation-$conversationId").subscribe()
    }
}
