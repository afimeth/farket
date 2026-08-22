package com.farket.app.ui.messaging

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.farket.app.data.toSafeUserMessage
import com.farket.app.data.messaging.ConversationRow
import com.farket.app.data.messaging.MessageRow
import com.farket.app.data.messaging.MessagingRepository
import com.farket.app.data.reports.ReportsRepository
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

data class ConversationDetailUiState(
    val isLoading: Boolean = true,
    val conversation: ConversationRow? = null,
    val otherUsername: String = "",
    val otherProfileId: String = "",
    val myUserId: String = "",
    val messages: List<MessageRow> = emptyList(),
    val isSending: Boolean = false,
    val errorMessage: String? = null,
    val reportSent: Boolean = false,
    val blocked: Boolean = false,
) {
    val isRecipient: Boolean
        get() = conversation != null && conversation.targetId == myUserId

    val isPending: Boolean
        get() = conversation?.status == "pending"

    val isBlocked: Boolean
        get() = conversation?.status == "blocked"

    val isDeclined: Boolean
        get() = conversation?.status == "declined"

    /** `char_limit_applied` her mesajda kayıtlı — pending durumda son mesajın sınırını kullan. */
    val charLimit: Int?
        get() = if (!isPending) null else messages.lastOrNull()?.charLimitApplied

    val canCompose: Boolean
        get() {
            val conv = conversation ?: return false
            if (conv.status != "pending" && conv.status != "accepted") return false
            // pending iken yalnızca isteği gönderen değil, karşı taraf (henüz kabul etmemiş
            // olsa bile) engellenmiyor — asıl kısıt backend'de: gönderen ikinci mesajı atamaz.
            if (!isPending) return true
            val lastSenderIsMe = messages.lastOrNull()?.senderId == myUserId
            return !lastSenderIsMe
        }
}

class ConversationDetailViewModel(
    private val repository: MessagingRepository,
    private val reportsRepository: ReportsRepository,
    private val supabase: SupabaseClient,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val conversationId: String = checkNotNull(savedStateHandle["conversationId"])

    private val _uiState = MutableStateFlow(ConversationDetailUiState())
    val uiState: StateFlow<ConversationDetailUiState> = _uiState.asStateFlow()

    init {
        val myUserId = supabase.auth.currentUserOrNull()?.id.orEmpty()
        _uiState.update { it.copy(myUserId = myUserId) }
        load()
        observeNewMessages()
    }

    private fun load() {
        _uiState.update { it.copy(isLoading = true, errorMessage = null) }
        viewModelScope.launch {
            runCatching {
                val conversation = repository.getConversation(conversationId)
                val myUserId = _uiState.value.myUserId
                val otherId = if (conversation.requesterId == myUserId) conversation.targetId else conversation.requesterId
                val otherUsername = repository.getUsername(conversationId)
                val messages = repository.listMessages(conversationId)
                Triple(conversation, otherId to otherUsername, messages)
            }.onSuccess { (conversation, otherIdAndUsername, messages) ->
                val (otherId, otherUsername) = otherIdAndUsername
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        conversation = conversation,
                        otherUsername = otherUsername,
                        otherProfileId = otherId,
                        messages = messages,
                    )
                }
            }.onFailure { error ->
                _uiState.update { it.copy(isLoading = false, errorMessage = error.toSafeUserMessage("Konuşma yüklenemedi")) }
            }
        }
    }

    private fun observeNewMessages() {
        viewModelScope.launch {
            // Realtime aboneliği canlılık iyileştirmesi; kurulamaz ya da bağlantı
            // koparsa sohbet ekranı çökmemeli — kullanıcı mesajları load() ile
            // görmeye devam eder, yalnızca anlık akış düşer.
            runCatching {
                repository.subscribeToChannel(conversationId)
                repository.newMessagesFlow(conversationId).collect { newMessage ->
                    _uiState.update { state ->
                        if (state.messages.any { it.id == newMessage.id }) return@update state
                        state.copy(messages = state.messages + newMessage)
                    }
                }
            }
        }
    }

    fun sendMessage(body: String) {
        val otherId = _uiState.value.let { state ->
            val conv = state.conversation ?: return
            if (conv.requesterId == state.myUserId) conv.targetId else conv.requesterId
        }
        _uiState.update { it.copy(isSending = true, errorMessage = null) }
        viewModelScope.launch {
            repository.sendMessage(otherId, body)
                .onSuccess { load() }
                .onFailure { error ->
                    _uiState.update { it.copy(isSending = false, errorMessage = error.toSafeUserMessage("Mesaj gönderilemedi")) }
                }
        }
    }

    fun accept() {
        viewModelScope.launch {
            repository.acceptConversation(conversationId)
                .onSuccess { load() }
                .onFailure { error ->
                    _uiState.update { it.copy(errorMessage = error.toSafeUserMessage("Kabul edilemedi")) }
                }
        }
    }

    fun decline() {
        viewModelScope.launch {
            repository.declineConversation(conversationId)
                .onSuccess { load() }
                .onFailure { error ->
                    _uiState.update { it.copy(errorMessage = error.toSafeUserMessage("Reddedilemedi")) }
                }
        }
    }

    fun report(reason: String) {
        val targetId = _uiState.value.otherProfileId
        viewModelScope.launch {
            reportsRepository.report(targetId, reason)
                .onSuccess { _uiState.update { it.copy(reportSent = true) } }
                .onFailure { error -> _uiState.update { it.copy(errorMessage = error.toSafeUserMessage("Şikayet gönderilemedi")) } }
        }
    }

    /** Engelleme aradaki açık konuşmayı backend'de otomatik kapatır — istemci ayrıca kapatmaya çalışmaz. */
    fun block() {
        val targetId = _uiState.value.otherProfileId
        viewModelScope.launch {
            reportsRepository.block(targetId)
                .onSuccess { _uiState.update { it.copy(blocked = true) }; load() }
                .onFailure { error -> _uiState.update { it.copy(errorMessage = error.toSafeUserMessage("Engellenemedi")) } }
        }
    }
}
