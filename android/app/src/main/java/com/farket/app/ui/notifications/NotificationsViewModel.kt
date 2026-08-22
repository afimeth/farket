package com.farket.app.ui.notifications

import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.ViewModel
import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.viewModelScope
import com.farket.app.data.notifications.NotificationRow
import com.farket.app.data.notifications.NotificationType
import com.farket.app.data.notifications.NotificationsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class NotificationsUiState(
    val isLoading: Boolean = true,
    val notifications: List<NotificationRow> = emptyList(),
    val errorMessage: String? = null,
)

class NotificationsViewModel(
    private val repository: NotificationsRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(NotificationsUiState())
    val uiState: StateFlow<NotificationsUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch {
            runCatching { repository.getMyNotifications() }
                .onSuccess { notifications -> _uiState.update { it.copy(isLoading = false, notifications = notifications) } }
                .onFailure { error ->
                    _uiState.update { it.copy(isLoading = false, errorMessage = error.toSafeUserMessage("Bildirimler yüklenemedi")) }
                }
        }
    }

    /**
     * Backend `get_my_notifications` dönüşünde `conversation_id` yok (yalnızca id/type/payload/
     * actor_username/read_at/created_at) — bu yüzden mesaj bildirimleri doğrudan konuşma
     * detayına değil, konuşma listesine yönlendirilir (bkz. DURUM.md bölüm 8).
     */
    fun onNotificationClicked(notification: NotificationRow, onOpenConversations: () -> Unit) {
        viewModelScope.launch {
            repository.markRead(notification.id)
            _uiState.update { state ->
                state.copy(
                    notifications = state.notifications.map {
                        if (it.id == notification.id) it.copy(readAt = it.readAt ?: "now") else it
                    },
                )
            }
        }
        if (notification.type in NotificationType.CONVERSATION_LINKED) {
            onOpenConversations()
        }
    }
}
