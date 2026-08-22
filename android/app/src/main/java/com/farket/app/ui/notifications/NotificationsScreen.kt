package com.farket.app.ui.notifications

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.farket.app.data.notifications.NotificationRow
import com.farket.app.data.notifications.NotificationType
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.common.EmptyState
import com.farket.app.ui.theme.LocalFarketColors
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive

/**
 * Bildirim listesi — bkz. proje notları FARKET_PROMPTLAR.md Prompt 8. Kimliksiz tipler
 * (quiz_started/identity_revealed/quiz_passed/perfect_score) toplu mesaj olarak gösterilir,
 * message_request/request_accepted gönderenin kullanıcı adıyla gösterilir.
 */
@Composable
fun NotificationsScreen(
    onOpenConversations: () -> Unit,
    viewModel: NotificationsViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()
    val colors = LocalFarketColors.current

    Column(modifier = Modifier.fillMaxSize().padding(20.dp)) {
        Text("Bildirimler", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(bottom = 16.dp))

        if (uiState.errorMessage != null) {
            Text(uiState.errorMessage!!, color = MaterialTheme.colorScheme.error)
        }

        if (uiState.isLoading) {
            CircularProgressIndicator(color = colors.accent)
        } else if (uiState.notifications.isEmpty()) {
            EmptyState("Henüz bir bildirimin yok.")
        } else {
            LazyColumn {
                items(uiState.notifications, key = { it.id }) { notification ->
                    NotificationItem(
                        notification = notification,
                        onClick = { viewModel.onNotificationClicked(notification, onOpenConversations) },
                    )
                    HorizontalDivider(color = colors.line)
                }
            }
        }
    }
}

@Composable
private fun NotificationItem(notification: NotificationRow, onClick: () -> Unit) {
    val colors = LocalFarketColors.current
    val isUnread = notification.readAt == null
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .background(if (isUnread) colors.veil else colors.surface)
            .padding(vertical = 12.dp, horizontal = 8.dp),
    ) {
        Text(notificationText(notification), style = MaterialTheme.typography.bodyLarge)
        Text(
            text = notification.createdAt,
            style = MaterialTheme.typography.labelSmall,
            color = colors.textFaint,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

private fun notificationText(notification: NotificationRow): String {
    val count = (notification.payload as? JsonObject)?.get("count")?.jsonPrimitive?.intOrNull ?: 1
    return when (notification.type) {
        NotificationType.QUIZ_STARTED -> "$count kişi bugün profilini quizledi"
        NotificationType.IDENTITY_REVEALED -> "$count kişi bugün künyeni açtı"
        NotificationType.QUIZ_PASSED -> "$count kişi bugün quizini geçti"
        NotificationType.PERFECT_SCORE -> "$count kişi bugün quizinde tam puan aldı"
        NotificationType.MESSAGE_REQUEST -> "@${notification.actorUsername ?: "?"} sana mesaj isteği gönderdi"
        NotificationType.REQUEST_ACCEPTED -> "@${notification.actorUsername ?: "?"} mesaj isteğini kabul etti"
        NotificationType.QUIZ_PROGRESS -> {
            val position = notification.progressCurrent
            val score = notification.progressScore
            if (position != null && score != null) {
                "Birisi quizini sürdürüyor — $position. soru, $score doğru"
            } else {
                "Birisi quizini sürdürüyor"
            }
        }
        NotificationType.NEAR_MISS -> "Birisi kıl payı kaçırdı, tekrar deneyebilir"
        NotificationType.REQUEST_EXPIRED -> "Bir mesaj isteğinin süresi doldu"
        NotificationType.WEEKLY_DIGEST -> "Haftalık özetin hazır"
        else -> notification.type
    }
}
