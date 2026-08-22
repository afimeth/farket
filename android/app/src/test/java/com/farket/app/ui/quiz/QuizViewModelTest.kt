package com.farket.app.ui.quiz

import androidx.lifecycle.SavedStateHandle
import com.farket.app.data.quiz.QuizOption
import com.farket.app.data.quiz.QuizQuestion
import com.farket.app.data.quiz.QuizRepository
import com.farket.app.data.quiz.StartQuizResult
import com.farket.app.data.quiz.SubmitAnswerResult
import io.mockk.coEvery
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

private const val ATTEMPT_ID = "attempt-1"
private const val TARGET_PROFILE_ID = "target-1"

/**
 * `QuizViewModel` Android'e bağımlı olmayan saf bir state machine — bu yüzden testler
 * Robolectric/emulator gerektirmeden burada (unit test kaynak seti) çalışır. `viewModelScope`
 * `Dispatchers.Main`'e bağlı olduğundan testte `UnconfinedTestDispatcher` ile değiştiriyoruz.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class QuizViewModelTest {

    private val repository = mockk<QuizRepository>()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun tenQuestions(): List<QuizQuestion> = (1..10).map { position ->
        QuizQuestion(
            position = position,
            questionBody = "Soru $position",
            options = listOf(QuizOption(id = "opt-$position-a", body = "A"), QuizOption(id = "opt-$position-b", body = "B")),
        )
    }

    private fun createViewModel(): QuizViewModel {
        coEvery { repository.startQuiz(TARGET_PROFILE_ID) } returns
            Result.success(StartQuizResult(attemptId = ATTEMPT_ID, questions = tenQuestions()))
        val savedStateHandle = SavedStateHandle(mapOf("profileId" to TARGET_PROFILE_ID))
        return QuizViewModel(repository, savedStateHandle)
    }

    @Test
    fun `start_quiz basarili olunca ilk soru gosterilir`() {
        val viewModel = createViewModel()

        val state = viewModel.uiState.value
        assertTrue(state is QuizUiState.Question)
        assertEquals(1, (state as QuizUiState.Question).position)
    }

    @Test
    fun `checkpoint gecilirse devam et ile 6 soruya ilerler`() {
        val viewModel = createViewModel()

        // Pozisyon 1-4: sıradan cevaplar, checkpoint/tier alanı gelmiyor.
        for (position in 1..4) {
            coEvery {
                repository.submitAnswer(ATTEMPT_ID, position, "opt-$position-a")
            } returns Result.success(SubmitAnswerResult(score = position))
            viewModel.answer("opt-$position-a")
        }

        // Pozisyon 5: checkpoint geçildi.
        coEvery {
            repository.submitAnswer(ATTEMPT_ID, 5, "opt-5-a")
        } returns Result.success(SubmitAnswerResult(score = 5, checkpointPassed = true))
        viewModel.answer("opt-5-a")

        val checkpointState = viewModel.uiState.value
        assertTrue(checkpointState is QuizUiState.CheckpointResult)
        assertTrue((checkpointState as QuizUiState.CheckpointResult).passed)

        viewModel.continueAfterCheckpoint()

        val nextState = viewModel.uiState.value
        assertTrue(nextState is QuizUiState.Question)
        assertEquals(6, (nextState as QuizUiState.Question).position)
    }

    @Test
    fun `checkpoint kaybedilirse elenir ve devam etmez`() {
        val viewModel = createViewModel()

        for (position in 1..4) {
            coEvery {
                repository.submitAnswer(ATTEMPT_ID, position, "opt-$position-a")
            } returns Result.success(SubmitAnswerResult(score = 0))
            viewModel.answer("opt-$position-a")
        }

        coEvery {
            repository.submitAnswer(ATTEMPT_ID, 5, "opt-5-a")
        } returns Result.success(SubmitAnswerResult(score = 3, checkpointPassed = false))
        viewModel.answer("opt-5-a")

        val state = viewModel.uiState.value
        assertTrue(state is QuizUiState.CheckpointResult)
        assertTrue(!(state as QuizUiState.CheckpointResult).passed)

        // Elenmiş bir denemede "devam et" hiçbir şey yapmamalı (kalan sorular gönderilmemeli).
        viewModel.continueAfterCheckpoint()
        assertTrue(viewModel.uiState.value is QuizUiState.CheckpointResult)
    }

    @Test
    fun `10 soru sonunda unlocked tier ile sonuclanir`() {
        val viewModel = createViewModel()

        for (position in 1..4) {
            coEvery {
                repository.submitAnswer(ATTEMPT_ID, position, "opt-$position-a")
            } returns Result.success(SubmitAnswerResult(score = position))
            viewModel.answer("opt-$position-a")
        }
        coEvery {
            repository.submitAnswer(ATTEMPT_ID, 5, "opt-5-a")
        } returns Result.success(SubmitAnswerResult(score = 5, checkpointPassed = true))
        viewModel.answer("opt-5-a")
        viewModel.continueAfterCheckpoint()

        for (position in 6..9) {
            coEvery {
                repository.submitAnswer(ATTEMPT_ID, position, "opt-$position-a")
            } returns Result.success(SubmitAnswerResult(score = position))
            viewModel.answer("opt-$position-a")
        }

        coEvery {
            repository.submitAnswer(ATTEMPT_ID, 10, "opt-10-a")
        } returns Result.success(SubmitAnswerResult(score = 8, unlockedTier = 8, status = "passed"))
        viewModel.answer("opt-10-a")

        val state = viewModel.uiState.value
        assertTrue(state is QuizUiState.Finished)
        assertEquals(8, (state as QuizUiState.Finished).unlockedTier)
        assertEquals(TARGET_PROFILE_ID, state.targetProfileId)
    }
}
