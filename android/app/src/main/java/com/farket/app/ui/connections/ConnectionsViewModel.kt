package com.farket.app.ui.connections

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.farket.app.data.connections.ConnectionRow
import com.farket.app.data.connections.ConnectionsRepository
import com.farket.app.data.toSafeUserMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ConnectionsUiState(
    val isLoading: Boolean = true,
    val connections: List<ConnectionRow> = emptyList(),
    val errorMessage: String? = null,
    val isRemoving: Boolean = false,
    val message: String? = null,
)

class ConnectionsViewModel(
    private val repository: ConnectionsRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ConnectionsUiState())
    val uiState: StateFlow<ConnectionsUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch {
            repository.listConnections()
                .onSuccess { rows ->
                    _uiState.update { it.copy(isLoading = false, connections = rows) }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(isLoading = false, errorMessage = error.toSafeUserMessage("Bağlantılar yüklenemedi"))
                    }
                }
        }
    }

    /**
     * Bağlantıyı sonlandırır. Geri alınamaz — çağıran ekran önce onay diyaloğu gösterir.
     */
    fun removeConnection(profileId: String) {
        _uiState.update { it.copy(isRemoving = true, errorMessage = null, message = null) }
        viewModelScope.launch {
            repository.removeConnection(profileId)
                .onSuccess {
                    _uiState.update {
                        it.copy(isRemoving = false, message = "Bağlantı sonlandırıldı, sohbet kapatıldı.")
                    }
                    refresh()
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(isRemoving = false, errorMessage = error.toSafeUserMessage("Bağlantı sonlandırılamadı"))
                    }
                }
        }
    }
}
