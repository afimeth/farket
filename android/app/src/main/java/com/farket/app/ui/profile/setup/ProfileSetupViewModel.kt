package com.farket.app.ui.profile.setup

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.farket.app.data.profile.CityRow
import com.farket.app.data.toSafeUserMessage
import com.farket.app.data.profile.DraftProgress
import com.farket.app.data.profile.IdentityAttributeDraft
import com.farket.app.data.profile.IdentityAttributeRow
import com.farket.app.data.profile.ProfileSetupRepository
import com.farket.app.data.profile.PublishProfileResult
import com.farket.app.data.profile.QuestionTemplateRow
import com.farket.app.data.profile.TaxonomyItemRow
import com.farket.app.data.profile.TemplateOptionRow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

enum class SetupStep {
    BASIC_INFO, AGE_ATTESTATION, USERNAME, IDENTITY_CARD, IDENTITY_ATTRIBUTES, PHOTOS,
    TEMPLATE_ANSWERS_ACT1, TEMPLATE_ANSWERS_ACT2_HARD, CUSTOM_QUESTION, PUBLISH,
}

private const val MIN_ACT1_ANSWERS = 7
private const val MIN_ACT2_HARD_ANSWERS = 3
private const val MIN_PHOTOS = 5
private const val MAX_PHOTOS = 7

data class TemplateOptionsState(
    val templateId: Int,
    val fixedOptions: List<TemplateOptionRow>? = null,
    val taxonomyItems: List<TaxonomyItemRow>? = null,
)

data class ProfileSetupUiState(
    val step: SetupStep = SetupStep.BASIC_INFO,
    val isLoading: Boolean = false,
    /**
     * Sunucudaki mevcut ilerlemenin ilk kez okunup okunmadığını ayırt eder — bkz.
     * ProfileSetupScreen'deki not: bu `false` iken tam ekran spinner gösterilir (henüz
     * hangi adımda olunduğu bilinmiyor); `true` olduktan sonra `isLoading`, adım
     * composable'ını değiştirmeden yalnızca ince bir üst katman olarak gösterilir —
     * aksi halde her gönderim denemesinde (başarısız olsa bile) formun tamamı
     * (remember edilen tüm alanlar) sıfırlanıyordu.
     */
    val hasResolvedInitialStep: Boolean = false,
    val errorMessage: String? = null,

    val cities: List<CityRow> = emptyList(),

    val ageAttested: Boolean = false,
    val identityAttributes: List<IdentityAttributeRow> = emptyList(),

    val photoCount: Int = 0,

    val act1Templates: List<QuestionTemplateRow> = emptyList(),
    val act1Answered: Set<Int> = emptySet(),
    val act2HardTemplates: List<QuestionTemplateRow> = emptyList(),
    val act2HardAnswered: Set<Int> = emptySet(),
    val optionsByTemplateId: Map<Int, TemplateOptionsState> = emptyMap(),

    val customQuestionSubmitted: Boolean = false,

    val publishResult: PublishProfileResult? = null,
) {
    val act1Progress: Int get() = act1Answered.size
    val act2HardProgress: Int get() = act2HardAnswered.size
    val canAdvanceFromPhotos: Boolean get() = photoCount in MIN_PHOTOS..MAX_PHOTOS
    val canAdvanceFromAct1: Boolean get() = act1Progress >= MIN_ACT1_ANSWERS
    val canAdvanceFromAct2Hard: Boolean get() = act2HardProgress >= MIN_ACT2_HARD_ANSWERS
}

class ProfileSetupViewModel(
    private val repository: ProfileSetupRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ProfileSetupUiState())
    val uiState: StateFlow<ProfileSetupUiState> = _uiState.asStateFlow()

    init {
        loadCities()
        resumeProgress()
    }

    /**
     * Bulgu (frontend, kritik): daha önce bu sihirbaz, adım/foto sayısı/cevaplanan soruları
     * yalnızca bellekte tutuyordu — süreç öldürülüp uygulama yeniden açıldığında sunucuda
     * kayıtlı ilerlemeye rağmen 1. adıma resetleniyordu. Artık ViewModel her oluşturulduğunda
     * sunucudaki mevcut ilerlemeyi okuyup kaldığı adımdan devam ediyor.
     */
    private fun resumeProgress() {
        _uiState.update { it.copy(isLoading = true) }
        viewModelScope.launch {
            runCatching { repository.getDraftProgress() }
                .onSuccess { progress ->
                    val step = determineResumeStep(progress)
                    _uiState.update {
                        it.copy(
                            isLoading = false,
                            hasResolvedInitialStep = true,
                            step = step,
                            ageAttested = progress.ageAttested,
                            photoCount = progress.photoCount,
                            act1Answered = progress.act1Answered,
                            act2HardAnswered = progress.act2HardAnswered,
                            customQuestionSubmitted = progress.hasCustomQuestion,
                        )
                    }
                    when (step) {
                        SetupStep.IDENTITY_ATTRIBUTES -> loadIdentityAttributes()
                        SetupStep.TEMPLATE_ANSWERS_ACT1 -> loadAct1Templates()
                        SetupStep.TEMPLATE_ANSWERS_ACT2_HARD -> loadAct2HardTemplates()
                        else -> Unit
                    }
                }
                .onFailure { error ->
                    _uiState.update { it.copy(hasResolvedInitialStep = true) }
                    setError(error)
                }
        }
    }

    private fun determineResumeStep(progress: DraftProgress): SetupStep = when {
        !progress.hasBasicInfo -> SetupStep.BASIC_INFO
        !progress.ageAttested -> SetupStep.AGE_ATTESTATION
        !progress.hasUsername -> SetupStep.USERNAME
        !progress.hasIdentityCard -> SetupStep.IDENTITY_CARD
        !progress.hasQuizEligibleAttribute -> SetupStep.IDENTITY_ATTRIBUTES
        progress.photoCount < MIN_PHOTOS -> SetupStep.PHOTOS
        progress.act1Answered.size < MIN_ACT1_ANSWERS -> SetupStep.TEMPLATE_ANSWERS_ACT1
        progress.act2HardAnswered.size < MIN_ACT2_HARD_ANSWERS -> SetupStep.TEMPLATE_ANSWERS_ACT2_HARD
        !progress.hasCustomQuestion -> SetupStep.CUSTOM_QUESTION
        else -> SetupStep.PUBLISH
    }

    private fun loadCities() {
        viewModelScope.launch {
            runCatching { repository.listCities() }
                .onSuccess { cities -> _uiState.update { it.copy(cities = cities) } }
                .onFailure { error -> setError(error) }
        }
    }

    fun submitBasicInfo(displayName: String, birthDate: String, sex: String, cityId: Int) {
        runStep {
            repository.createBasicProfile(displayName, birthDate, sex, cityId)
            advanceTo(SetupStep.AGE_ATTESTATION)
        }
    }

    fun confirmAge() {
        runStep {
            repository.attestAge()
            _uiState.update { it.copy(ageAttested = true) }
            advanceTo(SetupStep.USERNAME)
        }
    }

    fun submitUsername(username: String) {
        runStep {
            repository.setUsername(username)
            advanceTo(SetupStep.IDENTITY_CARD)
        }
    }

    fun submitIdentityCard(
        showName: Boolean,
        showAge: Boolean,
        showOccupation: Boolean,
        showCity: Boolean,
        showIntent: Boolean,
        occupation: String?,
        intent: String,
    ) {
        runStep {
            repository.createIdentityCard(showName, showAge, showOccupation, showCity, showIntent, occupation, intent)
            advanceTo(SetupStep.IDENTITY_ATTRIBUTES)
            loadIdentityAttributes()
        }
    }

    private fun loadIdentityAttributes() {
        viewModelScope.launch {
            runCatching { repository.listIdentityAttributes() }
                .onSuccess { attributes -> _uiState.update { it.copy(identityAttributes = attributes) } }
                .onFailure { error -> setError(error) }
        }
    }

    fun submitIdentityAttributes(attributes: List<IdentityAttributeDraft>) {
        runStep {
            repository.submitIdentityAttributes(attributes)
            advanceTo(SetupStep.PHOTOS)
            loadAct1Templates()
        }
    }

    fun uploadPhoto(thumbBytes: ByteArray, fullBytes: ByteArray, extension: String) {
        uploadPhotos(listOf(ProcessedPhoto(thumbBytes, fullBytes, extension)))
    }

    /**
     * Birden fazla fotoğrafı SIRAYLA yükler (tek coroutine içinde, bir sonrakine geçmeden
     * önce `photoCount` state güncellemesini bekleyerek) — çoklu seçim sonrası her fotoğraf
     * için ayrı ayrı `uploadPhoto()` çağırmak, her çağrı kendi coroutine'ini başlatıp aynı anda
     * `_uiState.value.photoCount`'u okuyacağından `position` çakışmasına (aynı pozisyon iki kez,
     * `(profile_id, position)` unique kısıtına takılma) yol açardı.
     */
    fun uploadPhotos(photos: List<ProcessedPhoto>) {
        if (photos.isEmpty()) return
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch { uploadProcessedPhotos(photos) }
    }

    /**
     * Seçilen görselleri önce işler, sonra yükler — ikisi de ViewModel'de.
     *
     * Bu iş eskiden `PhotosStep` içindeki `rememberCoroutineScope()` ile yapılıyordu ve
     * fotoğraf hiçbir zaman yüklenmiyordu: seçici callback'i tetikleniyor ama sonrasında
     * hiçbir şey olmuyordu. Nedeni, MainActivity'nin `launchMode="singleTask"` olması
     * (e-posta giriş linkinin geri dönüşü için gerekli, bkz. AndroidManifest.xml):
     * sistem fotoğraf seçicisinden dönerken görev yeniden kurulup Activity yeniden
     * yaratılabiliyor, o anda kompozisyon atılmış oluyor ve ona bağlı scope iptal
     * edildiği için `scope.launch { }` gövdesi hiç çalışmıyordu. `viewModelScope`
     * kompozisyondan bağımsız olduğu için bu yola dayanıklı.
     *
     * ContentResolver parametre olarak alınır, saklanmaz — ViewModel'in Context tutması
     * sızıntı riski.
     */
    fun addPhotosFromUris(contentResolver: android.content.ContentResolver, uris: List<android.net.Uri>) {
        if (uris.isEmpty()) return
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch {
            val processed = uris.mapNotNull { PhotoProcessor.process(contentResolver, it) }
            if (processed.isEmpty()) {
                _uiState.update {
                    it.copy(isLoading = false, errorMessage = "Fotoğraf okunamadı. Başka bir görsel deneyebilirsin.")
                }
                return@launch
            }
            uploadProcessedPhotos(processed)
        }
    }

    private suspend fun uploadProcessedPhotos(photos: List<ProcessedPhoto>) {
        for (photo in photos) {
            val position = _uiState.value.photoCount + 1
            if (position > MAX_PHOTOS) break
            val result = runCatching {
                repository.uploadPhoto(position, photo.thumbBytes, photo.fullBytes, photo.extension)
            }
            if (result.isFailure) {
                setError(result.exceptionOrNull())
                return
            }
            _uiState.update { it.copy(photoCount = it.photoCount + 1) }
        }
        _uiState.update { it.copy(isLoading = false) }
    }

    fun finishPhotosStep() {
        advanceTo(SetupStep.TEMPLATE_ANSWERS_ACT1)
    }

    private fun loadAct1Templates() {
        viewModelScope.launch {
            runCatching { repository.listTemplates(act = 1, hardOnly = false) }
                .onSuccess { templates -> _uiState.update { it.copy(act1Templates = templates) } }
                .onFailure { error -> setError(error) }
        }
    }

    private fun loadAct2HardTemplates() {
        viewModelScope.launch {
            runCatching { repository.listTemplates(act = 2, hardOnly = true) }
                .onSuccess { templates -> _uiState.update { it.copy(act2HardTemplates = templates) } }
                .onFailure { error -> setError(error) }
        }
    }

    fun loadOptionsFor(template: QuestionTemplateRow) {
        if (_uiState.value.optionsByTemplateId.containsKey(template.id)) return
        viewModelScope.launch {
            runCatching {
                if (template.taxonomyId != null) {
                    TemplateOptionsState(template.id, taxonomyItems = repository.getTaxonomyItems(template.taxonomyId))
                } else {
                    TemplateOptionsState(template.id, fixedOptions = repository.listTemplateOptions(template.id))
                }
            }.onSuccess { state ->
                _uiState.update { it.copy(optionsByTemplateId = it.optionsByTemplateId + (template.id to state)) }
            }.onFailure { error -> setError(error) }
        }
    }

    fun answerTemplate(templateId: Int, isAct2Hard: Boolean, selectedOptionId: Int?, selectedItemId: Int?) {
        viewModelScope.launch {
            runCatching { repository.setTemplateAnswer(templateId, selectedOptionId, selectedItemId) }
                .onSuccess {
                    _uiState.update { state ->
                        if (isAct2Hard) {
                            state.copy(act2HardAnswered = state.act2HardAnswered + templateId)
                        } else {
                            state.copy(act1Answered = state.act1Answered + templateId)
                        }
                    }
                }
                .onFailure { error -> setError(error) }
        }
    }

    fun finishAct1Step() {
        advanceTo(SetupStep.TEMPLATE_ANSWERS_ACT2_HARD)
        loadAct2HardTemplates()
    }

    fun finishAct2HardStep() {
        advanceTo(SetupStep.CUSTOM_QUESTION)
    }

    fun submitCustomQuestion(body: String, optionBodies: List<String>, correctOptionIndex: Int) {
        runStep {
            repository.createCustomQuestion(body, optionBodies, correctOptionIndex)
            _uiState.update { it.copy(customQuestionSubmitted = true) }
            advanceTo(SetupStep.PUBLISH)
        }
    }

    fun publish() {
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch {
            repository.publishProfile()
                .onSuccess { result -> _uiState.update { it.copy(isLoading = false, publishResult = result) } }
                .onFailure { error -> setError(error) }
        }
    }

    private fun advanceTo(step: SetupStep) {
        _uiState.update { it.copy(step = step, isLoading = false, errorMessage = null) }
    }

    private fun runStep(block: suspend () -> Unit) {
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch {
            runCatching { block() }
                .onSuccess { _uiState.update { it.copy(isLoading = false) } }
                .onFailure { error -> setError(error) }
        }
    }

    private fun setError(error: Throwable?) {
        val message = error?.toSafeUserMessage("Beklenmedik bir hata oluştu") ?: "Beklenmedik bir hata oluştu"
        _uiState.update { it.copy(isLoading = false, errorMessage = message) }
    }
}
