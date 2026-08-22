package com.farket.app.ui.auth

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.farket.app.BuildConfig
import com.farket.app.data.auth.AuthRepository
import com.farket.app.data.toSafeUserMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface LoginUiState {
    data object EnterEmail : LoginUiState
    data object SendingLink : LoginUiState
    data class WaitingForLink(val email: String) : LoginUiState
    data class EnterTestCode(val email: String, val submitting: Boolean = false) : LoginUiState
    data class Error(val message: String, val email: String?, val isTestCodeFlow: Boolean = false) : LoginUiState
}

/** Beta test kodu — ekranda gösterilir, gerçek güvenlik sınırı değildir (bkz. DOCTOR.md). */
const val BETA_TEST_LOGIN_CODE = "123456"

/**
 * Oturum açma başarısı burada değil, global `sessionStatus` akışında ele
 * alınır (bkz. MainActivity/FarketApp) — kullanıcı e-postadaki linke
 * dokununca uygulama deep-link ile açılır ve SDK oturumu kendisi kurar.
 * Bu ViewModel yalnızca "link gönder" isteğini ve bekleme ekranını yönetir.
 */
class AuthViewModel(
    private val authRepository: AuthRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow<LoginUiState>(LoginUiState.EnterEmail)
    val uiState: StateFlow<LoginUiState> = _uiState.asStateFlow()

    fun sendLoginLink(email: String) {
        val trimmed = email.trim()
        _uiState.value = LoginUiState.SendingLink
        viewModelScope.launch {
            authRepository.sendLoginLink(trimmed)
                .onSuccess { _uiState.value = LoginUiState.WaitingForLink(trimmed) }
                .onFailure { error ->
                    _uiState.value = LoginUiState.Error(userFacingMessage(error, "Bağlantı gönderilemedi"), email = null)
                }
        }
    }

    fun backToEmailEntry() {
        _uiState.value = LoginUiState.EnterEmail
    }

    /**
     * Beta test kısayolu: gerçek mail beklemeden sabit kod ekranına geçer.
     *
     * Yalnızca BETA_TEST_LOGIN açık derlemelerde çalışır — herkese açık dağıtımda
     * arayüzde hiç görünmez, buraya bir yoldan gelinse bile sessizce yok sayılır.
     */
    fun goToTestCodeEntry(email: String) {
        if (!BuildConfig.BETA_TEST_LOGIN) return
        _uiState.value = LoginUiState.EnterTestCode(email.trim())
    }

    fun submitTestCode(email: String, code: String) {
        if (!BuildConfig.BETA_TEST_LOGIN) return
        val trimmedEmail = email.trim()
        _uiState.value = LoginUiState.EnterTestCode(trimmedEmail, submitting = true)
        viewModelScope.launch {
            authRepository.signInWithTestCode(trimmedEmail, code)
                .onSuccess {
                    // Başarı: sessionStatus akışı Authenticated'e döner, MainActivity yönlendirir.
                }
                .onFailure { error ->
                    _uiState.value = LoginUiState.Error(
                        userFacingMessage(error, "Test kodu doğrulanamadı"),
                        email = trimmedEmail,
                        isTestCodeFlow = true,
                    )
                }
        }
    }

    private fun userFacingMessage(error: Throwable, fallback: String): String =
        if (error.message?.contains("rate limit", ignoreCase = true) == true) {
            "Çok sık denedin, birkaç saniye sonra tekrar dene."
        } else {
            error.toSafeUserMessage(fallback)
        }
}
