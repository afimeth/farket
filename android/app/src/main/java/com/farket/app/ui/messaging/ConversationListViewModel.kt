package com.farket.app.ui.messaging

import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.ViewModel
import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.viewModelScope
import com.farket.app.data.messaging.ConversationSummary
import com.farket.app.data.messaging.MessagingRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ConversationListUiState(
    val isLoading: Boolean = true,
    val conversations: List<ConversationSummary> = emptyList(),
    val errorMessage: String? = null,
)

class ConversationListViewModel(
    private val repository: MessagingRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ConversationListUiState())
    val uiState: StateFlow<ConversationListUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch {
            runCatching { repository.listMyConversations() }
                .onSuccess { conversations -> _uiState.update { it.copy(isLoading = false, conversations = conversations) } }
                .onFailure { error ->
                    _uiState.update { it.copy(isLoading = false, errorMessage = error.toSafeUserMessage("Konuşmalar yüklenemedi")) }
                }
        }
    }
}
