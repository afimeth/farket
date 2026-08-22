package com.farket.app.ui.messaging

import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.SavedStateHandle
import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.ViewModel
import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.viewModelScope
import com.farket.app.data.messaging.MessagingRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class NewMessageUiState(
    val isSending: Boolean = false,
    val errorMessage: String? = null,
    val createdConversationId: String? = null,
)

class NewMessageViewModel(
    private val repository: MessagingRepository,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val targetProfileId: String = checkNotNull(savedStateHandle["targetProfileId"])

    /** Backend `unlocked_tier`'a göre 7→50, ≥8→100 uyguluyor; bu yalnızca UI'da iyimser bir
     * ipucu — kesin doğrulama backend'de. */
    val optimisticCharLimit: Int? = savedStateHandle.get<Int>("unlockedTier")?.let { tier ->
        if (tier >= 8) 100 else if (tier == 7) 50 else null
    }

    private val _uiState = MutableStateFlow(NewMessageUiState())
    val uiState: StateFlow<NewMessageUiState> = _uiState.asStateFlow()

    fun send(body: String) {
        _uiState.update { it.copy(isSending = true, errorMessage = null) }
        viewModelScope.launch {
            repository.sendMessage(targetProfileId, body)
                .onSuccess { result -> _uiState.update { it.copy(isSending = false, createdConversationId = result.conversationId) } }
                .onFailure { error ->
                    _uiState.update { it.copy(isSending = false, errorMessage = error.toSafeUserMessage("Mesaj gönderilemedi")) }
                }
        }
    }
}
