package com.farket.app.data.quiz

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc

class QuizRepository(
    private val supabase: SupabaseClient,
) {
    /**
     * Hata durumları (bkz. proje notları): kendine/tekrar deneme, hedef engelli, hedef gizli
     * (3 ay), günlük kota (15) aşımı, yetersiz soru havuzu — hepsi backend'de sabit Türkçe
     * mesajlarla gelir, burada olduğu gibi UI'ya taşınır.
     */
    suspend fun startQuiz(targetProfileId: String): Result<StartQuizResult> = runCatching {
        supabase.postgrest.rpc(
            function = "start_quiz",
            parameters = StartQuizParams(targetProfileId = targetProfileId),
        ).decodeAs()
    }

    /**
     * Sorular sırayla cevaplanmalı, aksi halde `'Sorulara sırayla cevap vermelisin...'` hatası
     * gelir. Pozisyon 5'te `checkpointPassed`, pozisyon 10'da `unlockedTier`+`status` de dolu
     * gelir — çağıran taraf (ViewModel) bunlara göre akışı yönlendirir.
     */
    suspend fun submitAnswer(attemptId: String, position: Int, optionId: String): Result<SubmitAnswerResult> = runCatching {
        supabase.postgrest.rpc(
            function = "submit_answer",
            parameters = SubmitAnswerParams(attemptId = attemptId, position = position, optionId = optionId),
        ).decodeAs()
    }

    /** Bağlantı koptuğunda/ViewModel yeniden oluşturulduğunda deneme durumunu geri okumak için. */
    suspend fun checkCheckpoint(attemptId: String): Result<CheckCheckpointResult> = runCatching {
        supabase.postgrest.rpc(
            function = "check_checkpoint",
            parameters = AttemptIdParams(attemptId = attemptId),
        ).decodeAs()
    }

    /** İdempotent; normalde submit_answer 10. sorudan sonra otomatik çağırır. */
    suspend fun finishQuiz(attemptId: String): Result<FinishQuizResult> = runCatching {
        supabase.postgrest.rpc(
            function = "finish_quiz",
            parameters = AttemptIdParams(attemptId = attemptId),
        ).decodeAs()
    }

    /**
     * Günlük quiz hakkının nereden geldiğini gösterir. `get_quiz_allowance` ile aynı
     * hesabın tek kaynağı — backend'de o fonksiyon da bunun toplamını döndürüyor, yani
     * paneldeki sayı ile gerçek hak asla ayrışamaz.
     */
    suspend fun fetchAllowanceBreakdown(): Result<QuizAllowanceBreakdown> = runCatching {
        supabase.postgrest.rpc(function = "get_quiz_allowance_breakdown").decodeAs()
    }

    /** Kendi kalıp sorularının performansı; hangi soru "ölü" (otomatik pasife düşmüş). */
    suspend fun fetchQuizRadar(): Result<List<QuizRadarRow>> = runCatching {
        supabase.postgrest.rpc(function = "get_quiz_radar").decodeList()
    }

    /** İkinci deneme hakkı duran profiller — bekleyenler ve süresi dolmuş olanlar. */
    suspend fun fetchPendingRetries(): Result<List<PendingRetryRow>> = runCatching {
        supabase.postgrest.rpc(function = "get_my_pending_retries").decodeList()
    }

    /** Haftalık erken-ikinci-şans hakkı şu an kullanılabilir mi. */
    suspend fun fetchEarlyRetryStatus(): Result<EarlyRetryStatus> = runCatching {
        supabase.postgrest.rpc(function = "get_early_retry_status").decodeAs()
    }

    /**
     * Bir profilin ikinci deneme beklemesini erken bitirir (haftada 1 hak).
     *
     * Cezayı KALDIRMAZ: `retry_cost` kredisi start_retry'de yine ödenir ve ikinci
     * denemede tavan skor 8'de kalır — yalnızca bekleme öne çekilir. Hak bu hafta
     * kullanılmışsa backend Türkçe bir hata mesajıyla yenilenme tarihini döndürür.
     */
    suspend fun redeemEarlyRetry(targetProfileId: String): Result<RedeemEarlyRetryResult> = runCatching {
        supabase.postgrest.rpc(
            function = "redeem_early_retry",
            parameters = TargetProfileParams(targetProfileId = targetProfileId),
        ).decodeAs()
    }
}
