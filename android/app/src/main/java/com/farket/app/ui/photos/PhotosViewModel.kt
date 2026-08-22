package com.farket.app.ui.photos

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.farket.app.data.toSafeUserMessage
import com.farket.app.data.photos.MAX_PHOTOS
import com.farket.app.data.photos.MIN_PHOTOS
import com.farket.app.data.photos.PhotoRow
import com.farket.app.data.photos.PhotosRepository
import com.farket.app.ui.profile.setup.PhotoProcessor
import com.farket.app.ui.profile.setup.ProcessedPhoto
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class PhotosUiState(
    val isLoading: Boolean = true,
    val isUploading: Boolean = false,
    val photos: List<PhotoRow> = emptyList(),
    val thumbUrls: Map<String, String> = emptyMap(),
    val errorMessage: String? = null,
) {
    val canAddMore: Boolean get() = photos.size < MAX_PHOTOS
    val meetsMinimum: Boolean get() = photos.size >= MIN_PHOTOS
}

class PhotosViewModel(
    private val repository: PhotosRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(PhotosUiState())
    val uiState: StateFlow<PhotosUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch {
            runCatching { repository.listMyPhotos() }
                .onSuccess { photos ->
                    _uiState.update { it.copy(isLoading = false, photos = photos) }
                    loadSignedUrls(photos)
                }
                .onFailure { error -> setError(error) }
        }
    }

    private fun loadSignedUrls(photos: List<PhotoRow>) {
        viewModelScope.launch {
            val urls = mutableMapOf<String, String>()
            for (photo in photos) {
                runCatching { repository.createSignedThumbUrl(photo.storagePathThumb) }
                    .onSuccess { url -> urls[photo.id] = url }
            }
            _uiState.update { it.copy(thumbUrls = it.thumbUrls + urls) }
        }
    }

    fun uploadPhoto(thumbBytes: ByteArray, fullBytes: ByteArray, extension: String) {
        uploadPhotos(listOf(ProcessedPhoto(thumbBytes, fullBytes, extension)))
    }

    /**
     * Sırayla yükler — repository.uploadPhoto() bir sonraki `position`'ı DB'den okuyarak
     * hesaplıyor, bu yüzden çoklu seçimde paralel çağrılar aynı position'ı hesaplayıp
     * unique kısıtına takılabilir (bkz. ProfileSetupViewModel.uploadPhotos'taki aynı not).
     */
    /**
     * Seçilen görselleri önce işler, sonra yükler — ikisi de ViewModel'de.
     *
     * Çağıran tarafta `rememberCoroutineScope()` kullanmak yüklemeyi sessizce kırıyordu:
     * MainActivity `launchMode="singleTask"` ile çalıştığından (e-posta giriş linkinin
     * geri dönüşü için gerekli) sistem fotoğraf seçicisinden dönerken Activity yeniden
     * yaratılabiliyor, kompozisyona bağlı scope iptal oluyor ve `launch { }` gövdesi hiç
     * çalışmıyor. Aynı hata kurulum sihirbazının fotoğraf adımında da vardı.
     *
     * ContentResolver parametre olarak alınır, saklanmaz (ViewModel'de Context tutmak
     * sızıntı riski).
     */
    fun addPhotosFromUris(contentResolver: android.content.ContentResolver, uris: List<android.net.Uri>) {
        if (uris.isEmpty()) return
        _uiState.update { it.copy(isUploading = true, errorMessage = null) }
        viewModelScope.launch {
            val processed = uris.mapNotNull { PhotoProcessor.process(contentResolver, it) }
            if (processed.isEmpty()) {
                _uiState.update {
                    it.copy(isUploading = false, errorMessage = "Fotoğraf okunamadı. Başka bir görsel deneyebilirsin.")
                }
                return@launch
            }
            uploadPhotos(processed)
        }
    }

    fun uploadPhotos(photos: List<ProcessedPhoto>) {
        if (photos.isEmpty()) return
        _uiState.update { it.copy(isUploading = true, errorMessage = null) }
        viewModelScope.launch {
            for (photo in photos) {
                val result = runCatching {
                    repository.uploadPhoto(photo.thumbBytes, photo.fullBytes, photo.extension)
                }
                if (result.isFailure) {
                    val error = result.exceptionOrNull()
                    _uiState.update {
                        it.copy(
                            isUploading = false,
                            errorMessage = error?.toSafeUserMessage("Fotoğraf yüklenemedi"),
                        )
                    }
                    refresh()
                    return@launch
                }
            }
            _uiState.update { it.copy(isUploading = false) }
            refresh()
        }
    }

    fun deletePhoto(photo: PhotoRow) {
        viewModelScope.launch {
            runCatching { repository.deletePhoto(photo) }
                .onSuccess { refresh() }
                .onFailure { error -> setError(error) }
        }
    }

    fun moveUp(photo: PhotoRow) {
        val photos = _uiState.value.photos
        val index = photos.indexOf(photo)
        if (index <= 0) return
        swap(photo, photos[index - 1])
    }

    fun moveDown(photo: PhotoRow) {
        val photos = _uiState.value.photos
        val index = photos.indexOf(photo)
        if (index < 0 || index >= photos.size - 1) return
        swap(photo, photos[index + 1])
    }

    private fun swap(a: PhotoRow, b: PhotoRow) {
        viewModelScope.launch {
            runCatching { repository.swapPositions(a, b) }
                .onSuccess { refresh() }
                .onFailure { error -> setError(error) }
        }
    }

    private fun setError(error: Throwable) {
        _uiState.update {
            it.copy(isLoading = false, errorMessage = error.toSafeUserMessage("Beklenmedik bir hata oluştu"))
        }
    }
}
