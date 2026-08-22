package com.farket.app.ui.discovery

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.farket.app.data.discovery.DiscoverProfileRow
import com.farket.app.data.discovery.DiscoveryRepository
import com.farket.app.data.toSafeUserMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

// Backend'de iki ayrı günlük limit hatası var (bkz. discovery_functions.sql ve
// v41_quiz_allowance.sql) — biri keşif çağrısı kotası, diğeri kalıp soru destesi kotası.
// İkisi de aynı kullanıcı dostu mesaja eşleniyor, geri kalan her şey toSafeUserMessage'a düşer.
private val DAILY_QUOTA_MARKERS = listOf("Günlük keşif çağrı kotan doldu", "Günlük deste sınırına ulaştın")

data class DiscoveryUiState(
    val isLoading: Boolean = true,
    val cards: List<DiscoverProfileRow> = emptyList(),
    val coverUrls: Map<String, String> = emptyMap(),
    val photoUrls: Map<String, List<String>> = emptyMap(),
    val errorMessage: String? = null,
)

class DiscoveryViewModel(
    private val repository: DiscoveryRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(DiscoveryUiState())
    val uiState: StateFlow<DiscoveryUiState> = _uiState.asStateFlow()

    init {
        loadMore()
    }

    /**
     * `discover_profiles` bir offset/cursor parametresi almıyor (yalnızca `p_limit`) — her
     * çağrı, henüz atlanmamış/quiz'lenmemiş uygun profilleri rastgele sırayla döner. Bu yüzden
     * burada biriktirmek yerine listeyi TAZELİYORUZ: liste tükenince (tüm kartlar atlanınca)
     * tekrar çağrılması, backend'in artık dışladığı kartları hariç tutarak yeni bir set
     * getirmesini sağlar.
     */
    fun loadMore() {
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch {
            repository.discoverProfiles()
                .onSuccess { profiles ->
                    _uiState.update { it.copy(isLoading = false, cards = profiles) }
                    loadCoverUrls(profiles)
                    loadPhotoUrls(profiles)
                }
                .onFailure { error -> setError(error) }
        }
    }

    private fun loadCoverUrls(profiles: List<DiscoverProfileRow>) {
        viewModelScope.launch {
            val urls = mutableMapOf<String, String>()
            for (profile in profiles) {
                val path = profile.coverPhotoThumb ?: continue
                runCatching { repository.createSignedUrl(path) }
                    .onSuccess { url -> urls[profile.id] = url }
            }
            _uiState.update { it.copy(coverUrls = it.coverUrls + urls) }
        }
    }

    private fun loadPhotoUrls(profiles: List<DiscoverProfileRow>) {
        viewModelScope.launch {
            val urlsByProfile = mutableMapOf<String, List<String>>()
            for (profile in profiles) {
                if (profile.photos.isEmpty()) continue
                val signed = profile.photos.mapNotNull { path ->
                    runCatching { repository.createSignedUrl(path) }.getOrNull()
                }
                if (signed.isNotEmpty()) urlsByProfile[profile.id] = signed
            }
            _uiState.update { it.copy(photoUrls = it.photoUrls + urlsByProfile) }
        }
    }

    fun skip(profile: DiscoverProfileRow) {
        viewModelScope.launch {
            repository.skipProfile(profile.id)
                .onSuccess {
                    _uiState.update { it.copy(cards = it.cards.filterNot { c -> c.id == profile.id }) }
                }
                .onFailure { error -> setError(error) }
        }
    }

    private fun setError(error: Throwable) {
        val rawMessage = error.message
        val friendlyMessage = if (DAILY_QUOTA_MARKERS.any { rawMessage?.contains(it) == true }) {
            "Bugünlük keşif hakkın doldu, yarın tekrar dene"
        } else {
            error.toSafeUserMessage("Beklenmedik bir hata oluştu")
        }
        _uiState.update { it.copy(isLoading = false, errorMessage = friendlyMessage) }
    }
}
