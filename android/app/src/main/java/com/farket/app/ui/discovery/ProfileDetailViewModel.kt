package com.farket.app.ui.discovery

import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.SavedStateHandle
import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.ViewModel
import com.farket.app.data.toSafeUserMessage
import androidx.lifecycle.viewModelScope
import com.farket.app.data.discovery.DiscoveryRepository
import com.farket.app.data.discovery.PublicProfileResult
import com.farket.app.data.reports.ReportsRepository
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ProfileDetailUiState(
    val isLoading: Boolean = true,
    val profile: PublicProfileResult? = null,
    val photoUrls: Map<String, String> = emptyMap(),
    val errorMessage: String? = null,
    val reportSent: Boolean = false,
    val blocked: Boolean = false,
)

class ProfileDetailViewModel(
    private val repository: DiscoveryRepository,
    private val reportsRepository: ReportsRepository,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val profileId: String = checkNotNull(savedStateHandle["profileId"])

    private val _uiState = MutableStateFlow(ProfileDetailUiState())
    val uiState: StateFlow<ProfileDetailUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            repository.getPublicProfile(profileId)
                .onSuccess { profile ->
                    _uiState.update { it.copy(isLoading = false, profile = profile) }
                    loadPhotoUrls(profile)
                }
                .onFailure { error ->
                    _uiState.update { it.copy(isLoading = false, errorMessage = error.toSafeUserMessage("Profil yüklenemedi")) }
                }
        }
    }

    private fun loadPhotoUrls(profile: PublicProfileResult) {
        viewModelScope.launch {
            val urls = mutableMapOf<String, String>()
            for (photo in profile.photos) {
                runCatching { repository.createSignedUrl(photo.storagePathFull) }
                    .onSuccess { url -> urls[photo.id] = url }
            }
            _uiState.update { it.copy(photoUrls = it.photoUrls + urls) }
        }
    }

    fun report(reason: String) {
        viewModelScope.launch {
            reportsRepository.report(profileId, reason)
                .onSuccess { _uiState.update { it.copy(reportSent = true) } }
                .onFailure { error -> _uiState.update { it.copy(errorMessage = error.toSafeUserMessage("Şikayet gönderilemedi")) } }
        }
    }

    /** Engelleme aradaki açık konuşmayı backend'de otomatik kapatır. */
    fun block() {
        viewModelScope.launch {
            reportsRepository.block(profileId)
                .onSuccess { _uiState.update { it.copy(blocked = true) } }
                .onFailure { error -> _uiState.update { it.copy(errorMessage = error.toSafeUserMessage("Engellenemedi")) } }
        }
    }
}
