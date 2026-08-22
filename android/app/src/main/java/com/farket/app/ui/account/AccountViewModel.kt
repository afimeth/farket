package com.farket.app.ui.account

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.farket.app.data.account.AccountRepository
import com.farket.app.data.toSafeUserMessage
import com.farket.app.data.profile.IdentityAttributeDraft
import com.farket.app.data.profile.IdentityAttributeRow
import com.farket.app.data.profile.ProfileSetupRepository
import com.farket.app.data.quiz.PendingRetryRow
import com.farket.app.data.quiz.QuizAllowanceBreakdown
import com.farket.app.data.quiz.QuizRadarRow
import com.farket.app.data.quiz.QuizRepository
import com.farket.app.data.reports.BlockedUser
import com.farket.app.data.reports.ReportsRepository
import com.farket.app.data.verification.VerificationRepository
import com.farket.app.data.verification.VerificationStatus
import com.farket.app.ui.profile.setup.PhotoProcessor
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonElement

data class AccountUiState(
    val isLoading: Boolean = true,
    val isAccountDeleted: Boolean = false,
    val blockedUsers: List<BlockedUser> = emptyList(),
    val isBusy: Boolean = false,
    val message: String? = null,
    val errorMessage: String? = null,
    val verificationStatus: VerificationStatus = VerificationStatus.NONE,
    val isSubmittingVerification: Boolean = false,
    val identityAttributes: List<IdentityAttributeRow> = emptyList(),
    val isSavingIdentityAttributes: Boolean = false,
    /** null iken "Günlük hakkım" bölümü çizilmez (henüz yüklenmedi ya da çağrı başarısız). */
    val allowance: QuizAllowanceBreakdown? = null,
    val quizRadar: List<QuizRadarRow> = emptyList(),
    val shareQuizProgress: Boolean = true,
    val isSavingPrivacy: Boolean = false,
    val pendingRetries: List<PendingRetryRow> = emptyList(),
    val earlyRetryAvailable: Boolean = false,
    val earlyRetryNextAt: String? = null,
    val isRedeemingRetry: Boolean = false,
)

class AccountViewModel(
    private val accountRepository: AccountRepository,
    private val reportsRepository: ReportsRepository,
    private val verificationRepository: VerificationRepository,
    private val profileSetupRepository: ProfileSetupRepository,
    private val quizRepository: QuizRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(AccountUiState())
    val uiState: StateFlow<AccountUiState> = _uiState.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch {
            val isDeleted = runCatching { accountRepository.isAccountDeleted() }.getOrDefault(false)
            val blocked = runCatching { reportsRepository.listBlocked() }.getOrDefault(emptyList())
            val verificationStatus = runCatching { verificationRepository.getStatus() }
                .getOrDefault(VerificationStatus.NONE)
            val identityAttributes = runCatching { profileSetupRepository.listIdentityAttributes() }
                .getOrDefault(emptyList())
            // Bu üçü ekranın çalışması için zorunlu değil: başarısız olurlarsa ilgili
            // bölüm çizilmez, ayarların geri kalanı yine açılır.
            val allowance = quizRepository.fetchAllowanceBreakdown().getOrNull()
            val radar = quizRepository.fetchQuizRadar().getOrDefault(emptyList())
            val privacy = accountRepository.getPrivacySettings().getOrNull()
            val pending = quizRepository.fetchPendingRetries().getOrDefault(emptyList())
            val earlyRetry = quizRepository.fetchEarlyRetryStatus().getOrNull()
            _uiState.update {
                it.copy(
                    isLoading = false,
                    isAccountDeleted = isDeleted,
                    blockedUsers = blocked,
                    verificationStatus = verificationStatus,
                    identityAttributes = identityAttributes,
                    allowance = allowance,
                    quizRadar = radar,
                    shareQuizProgress = privacy?.shareQuizProgress ?: it.shareQuizProgress,
                    pendingRetries = pending,
                    earlyRetryAvailable = earlyRetry?.available ?: false,
                    earlyRetryNextAt = earlyRetry?.nextAvailableAt,
                )
            }
        }
    }

    /**
     * Bir profilin ikinci deneme beklemesini erken bitirir (haftada 1 hak). Cezayı
     * kaldırmaz — kredi yine ödenir, ikinci denemede tavan skor 8'de kalır.
     */
    fun redeemEarlyRetry(profileId: String) {
        _uiState.update { it.copy(isRedeemingRetry = true, errorMessage = null, message = null) }
        viewModelScope.launch {
            quizRepository.redeemEarlyRetry(profileId)
                .onSuccess {
                    _uiState.update {
                        it.copy(isRedeemingRetry = false, message = "Bekleme kaldırıldı, bu profili şimdi tekrar deneyebilirsin.")
                    }
                    refresh()
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(isRedeemingRetry = false, errorMessage = error.toSafeUserMessage("Hak kullanılamadı"))
                    }
                }
        }
    }

    /**
     * Anahtarı iyimser çevirir, backend reddederse eski değere döner — ayar ekranındaki
     * bir switch'in dokunma anında tepki vermesi gerekiyor.
     */
    fun setShareQuizProgress(value: Boolean) {
        val previous = _uiState.value.shareQuizProgress
        _uiState.update { it.copy(shareQuizProgress = value, isSavingPrivacy = true, errorMessage = null) }
        viewModelScope.launch {
            accountRepository.setShareQuizProgress(value)
                .onSuccess { _uiState.update { it.copy(isSavingPrivacy = false) } }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(
                            isSavingPrivacy = false,
                            shareQuizProgress = previous,
                            errorMessage = error.toSafeUserMessage("Ayar kaydedilemedi"),
                        )
                    }
                }
        }
    }

    fun saveIdentityAttributes(attributes: List<IdentityAttributeDraft>) {
        _uiState.update { it.copy(isSavingIdentityAttributes = true, errorMessage = null, message = null) }
        viewModelScope.launch {
            runCatching { profileSetupRepository.submitIdentityAttributes(attributes) }
                .onSuccess {
                    val identityAttributes = runCatching { profileSetupRepository.listIdentityAttributes() }
                        .getOrDefault(emptyList())
                    _uiState.update {
                        it.copy(
                            isSavingIdentityAttributes = false,
                            identityAttributes = identityAttributes,
                            message = "Künye bilgilerin güncellendi.",
                        )
                    }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(isSavingIdentityAttributes = false, errorMessage = error.toSafeUserMessage("Güncellenemedi"))
                    }
                }
        }
    }

    /**
     * Selfie'yi işleyip doğrulama başvurusunu gönderir — ikisi de ViewModel'de.
     *
     * Çağıran tarafta `rememberCoroutineScope()` kullanmak bu akışı sessizce kırıyor:
     * MainActivity `launchMode="singleTask"` olduğundan görsel seçiciden dönerken
     * Activity yeniden yaratılabiliyor ve kompozisyona bağlı scope iptal oluyor
     * (fotoğraf yükleme adımındaki aynı hata, bkz. PhotosViewModel.addPhotosFromUris).
     */
    fun submitVerificationFromUri(contentResolver: android.content.ContentResolver, uri: android.net.Uri) {
        _uiState.update { it.copy(isSubmittingVerification = true, errorMessage = null, message = null) }
        viewModelScope.launch {
            val processed = PhotoProcessor.process(contentResolver, uri)
            if (processed == null) {
                _uiState.update {
                    it.copy(isSubmittingVerification = false, errorMessage = "Görsel okunamadı. Başka bir fotoğraf dene.")
                }
                return@launch
            }
            verificationRepository.submit(processed.fullBytes, processed.extension)
                .onSuccess {
                    _uiState.update {
                        it.copy(
                            isSubmittingVerification = false,
                            verificationStatus = VerificationStatus.PENDING,
                            message = "Doğrulama başvurun alındı, incelenmesi biraz sürebilir.",
                        )
                    }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(isSubmittingVerification = false, errorMessage = error.toSafeUserMessage("Başvuru gönderilemedi"))
                    }
                }
        }
    }

    fun submitVerification(selfieBytes: ByteArray, extension: String) {
        _uiState.update { it.copy(isSubmittingVerification = true, errorMessage = null, message = null) }
        viewModelScope.launch {
            verificationRepository.submit(selfieBytes, extension)
                .onSuccess {
                    _uiState.update {
                        it.copy(
                            isSubmittingVerification = false,
                            verificationStatus = VerificationStatus.PENDING,
                            message = "Doğrulama başvurun alındı, incelenmesi biraz sürebilir.",
                        )
                    }
                }
                .onFailure { error ->
                    _uiState.update {
                        it.copy(isSubmittingVerification = false, errorMessage = error.toSafeUserMessage("Başvuru gönderilemedi"))
                    }
                }
        }
    }

    fun deleteAccount(onSignedOut: () -> Unit) {
        _uiState.update { it.copy(isBusy = true, errorMessage = null) }
        viewModelScope.launch {
            accountRepository.deleteAccount()
                .onSuccess {
                    accountRepository.signOut()
                    _uiState.update { it.copy(isBusy = false) }
                    onSignedOut()
                }
                .onFailure { error ->
                    _uiState.update { it.copy(isBusy = false, errorMessage = error.toSafeUserMessage("Hesap silinemedi")) }
                }
        }
    }

    fun restoreAccount() {
        _uiState.update { it.copy(isBusy = true, errorMessage = null, message = null) }
        viewModelScope.launch {
            accountRepository.restoreAccount()
                .onSuccess {
                    _uiState.update { it.copy(isBusy = false, message = "Hesabın geri alındı.") }
                    refresh()
                }
                .onFailure { error ->
                    _uiState.update { it.copy(isBusy = false, errorMessage = error.toSafeUserMessage("Hesap geri alınamadı")) }
                }
        }
    }

    fun unblock(profileId: String) {
        viewModelScope.launch {
            reportsRepository.unblock(profileId).onSuccess { refresh() }
        }
    }

    suspend fun exportData(): Result<JsonElement> = accountRepository.exportMyData()

    fun signOut(onSignedOut: () -> Unit) {
        viewModelScope.launch {
            accountRepository.signOut()
            onSignedOut()
        }
    }
}
