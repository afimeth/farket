package com.farket.app.ui.identity

import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.SavedStateHandle
import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.ViewModel
import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.viewModelScope
import com.farket.app.data.identity.IdentityRepository
import com.farket.app.data.identity.IdentityRevealResult
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface IdentityUiState {
    data object Loading : IdentityUiState
    data class Success(val result: IdentityRevealResult) : IdentityUiState
    data class Error(val message: String) : IdentityUiState
}

class IdentityViewModel(
    private val repository: IdentityRepository,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val attemptId: String = checkNotNull(savedStateHandle["attemptId"])

    private val _uiState = MutableStateFlow<IdentityUiState>(IdentityUiState.Loading)
    val uiState: StateFlow<IdentityUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            repository.revealIdentity(attemptId)
                .onSuccess { result -> _uiState.value = IdentityUiState.Success(result) }
                .onFailure { error -> _uiState.value = IdentityUiState.Error(error.toSafeUserMessage("Künye açılamadı")) }
        }
    }
}
