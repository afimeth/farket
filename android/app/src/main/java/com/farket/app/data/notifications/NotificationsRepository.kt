package com.farket.app.data.notifications

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc

class NotificationsRepository(
    private val supabase: SupabaseClient,
) {
    suspend fun getMyNotifications(limit: Int = 30): List<NotificationRow> =
        supabase.postgrest.rpc(
            function = "get_my_notifications",
            parameters = GetMyNotificationsParams(limit = limit),
        ).decodeAs()

    /** Başkasının bildirimini işaretlemek sessizce 0 satır etkiler, backend hata fırlatmaz. */
    suspend fun markRead(notificationId: String): Result<Unit> = runCatching {
        supabase.postgrest.rpc(
            function = "mark_notification_read",
            parameters = MarkNotificationReadParams(notificationId = notificationId),
        )
        Unit
    }
}
