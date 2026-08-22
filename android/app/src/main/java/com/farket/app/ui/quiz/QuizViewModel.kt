package com.farket.app.ui.quiz

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.farket.app.data.quiz.QuizQuestion
import com.farket.app.data.quiz.QuizRepository
import com.farket.app.data.toSafeUserMessage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

private const val CHECKPOINT_POSITION = 5
private const val LAST_POSITION = 10

sealed interface QuizUiState {
    data object Loading : QuizUiState
    data class Question(
        val position: Int,
        val question: QuizQuestion,
        val score: Int,
    ) : QuizUiState

    data class CheckpointResult(val passed: Boolean, val score: Int) : QuizUiState

    /** Checkpoint geçildikten hemen sonra gösterilen tebrikler + künye ekranı. */
    data class HeroCard(val score: Int, val identity: Map<String, String>) : QuizUiState

    data class Finished(
        val unlockedTier: Int,
        val status: String,
        val attemptId: String,
        val targetProfileId: String,
    ) : QuizUiState
    data class Error(val message: String) : QuizUiState
}

class QuizViewModel(
    private val repository: QuizRepository,
    savedStateHandle: SavedStateHandle,
) : ViewModel() {

    private val targetProfileId: String = checkNotNull(savedStateHandle["profileId"])

    private var attemptId: String? = null
    private var questionsByPosition: Map<Int, QuizQuestion> = emptyMap()

    private val _uiState = MutableStateFlow<QuizUiState>(QuizUiState.Loading)
    val uiState: StateFlow<QuizUiState> = _uiState.asStateFlow()

    init {
        startQuiz()
    }

    private fun startQuiz() {
        _uiState.value = QuizUiState.Loading
        viewModelScope.launch {
            repository.startQuiz(targetProfileId)
                .onSuccess { result ->
                    attemptId = result.attemptId
                    questionsByPosition = result.questions.associateBy { it.position }
                    val firstQuestion = questionsByPosition[1]
                    _uiState.value = if (firstQuestion != null) {
                        QuizUiState.Question(position = 1, question = firstQuestion, score = 0)
                    } else {
                        QuizUiState.Error("Bu profil şu an quizlenemiyor")
                    }
                }
                .onFailure { error -> _uiState.value = QuizUiState.Error(error.toSafeUserMessage("Quiz başlatılamadı")) }
        }
    }

    fun answer(optionId: String) {
        val currentAttemptId = attemptId ?: return
        val current = _uiState.value as? QuizUiState.Question ?: return

        viewModelScope.launch {
            repository.submitAnswer(currentAttemptId, current.position, optionId)
                .onSuccess { result ->
                    _uiState.value = when {
                        current.position == CHECKPOINT_POSITION && result.checkpointPassed == false -> {
                            QuizUiState.CheckpointResult(passed = false, score = result.score)
                        }
                        current.position == CHECKPOINT_POSITION && result.checkpointPassed == true -> {
                            QuizUiState.HeroCard(score = result.score, identity = result.identity.orEmpty())
                        }
                        current.position == LAST_POSITION -> {
                            QuizUiState.Finished(
                                unlockedTier = result.unlockedTier ?: 0,
                                status = result.status ?: "",
                                attemptId = currentAttemptId,
                                targetProfileId = targetProfileId,
                            )
                        }
                        else -> {
                            val nextPosition = current.position + 1
                            val nextQuestion = questionsByPosition[nextPosition]
                            if (nextQuestion != null) {
                                QuizUiState.Question(position = nextPosition, question = nextQuestion, score = result.score)
                            } else {
                                QuizUiState.Error("Beklenmedik bir durum oluştu (soru bulunamadı)")
                            }
                        }
                    }
                }
                .onFailure { error -> _uiState.value = QuizUiState.Error(error.toSafeUserMessage("Cevap gönderilemedi")) }
        }
    }

    /** Checkpoint'i geçtikten sonra hero card'ın "2. Bölüme Geç" butonuyla 6. soruya ilerlemek için. */
    fun continueAfterCheckpoint() {
        val state = _uiState.value as? QuizUiState.HeroCard ?: return
        val nextPosition = CHECKPOINT_POSITION + 1
        val nextQuestion = questionsByPosition[nextPosition] ?: run {
            _uiState.value = QuizUiState.Error("Beklenmedik bir durum oluştu (soru bulunamadı)")
            return
        }
        _uiState.value = QuizUiState.Question(position = nextPosition, question = nextQuestion, score = state.score)
    }
}

/** Faz 2 (pozisyon 6-10): profil sahibinin künye/serbest sorularını içerir, tamamlanmadan çıkılamaz. */
internal fun isExitGuardedPosition(position: Int): Boolean = position > CHECKPOINT_POSITION
