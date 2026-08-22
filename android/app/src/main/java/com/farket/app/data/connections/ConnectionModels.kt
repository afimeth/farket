package com.farket.app.data.connections

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * Bir "bağlantı" (`get_my_connections`).
 *
 * Ürün kuralı: bağlantı quiz çözmekle ya da ilk etabı geçmekle DEĞİL, yalnızca
 * KARŞILIKLI mesajlaşmayla kurulur — sohbette her iki tarafın da en az bir mesajı
 * olmalı. Tek taraflı gönderilen mesaj bağlantı saymaz.
 */
@Serializable
internal data class RemoveConnectionParams(
    @SerialName("p_profile_id") val profileId: String,
)

@Serializable
data class ConnectionRow(
    @SerialName("profile_id") val profileId: String,
    val username: String? = null,
    @SerialName("conversation_id") val conversationId: String,
    /** Karşılıklılığın sağlandığı an: iki taraftan geç kalanın ilk mesajı. */
    @SerialName("connected_at") val connectedAt: String? = null,
    @SerialName("last_message_at") val lastMessageAt: String? = null,
)
