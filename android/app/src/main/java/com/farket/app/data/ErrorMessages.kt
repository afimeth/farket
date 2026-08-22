package com.farket.app.data

import android.util.Log

/**
 * Bulgu (frontend/güvenlik, canlı testte bulundu): `error.message ?: fallback` deseni
 * uygulamada ~18 yerde tekrarlanıyordu — Supabase Kotlin SDK'sının (auth/postgrest/storage
 * fark etmeksizin) bir istek başarısız olduğunda ürettiği `.message`, isteğin tam URL'sini,
 * header'larını (Authorization/apikey'in uzunluğu dahil) ve HTTP metodunu içeren çok satırlı
 * ham bir teknik dökümdür — bu doğrudan kullanıcı ekranına basılıyordu (örn. profil kurulumunda
 * geçersiz bir doğum tarihi girildiğinde). Backend'in özenle Türkçeleştirilmiş `raise exception`
 * mesajları (bkz. proje notları) kısa/tek satırlık geldiği için bu sezgisel ayrım işe yarıyor:
 * kısa/tek satırlık mesajlar olduğu gibi gösterilir, uzun/çok satırlı teknik dökümler loglanıp
 * yerine güvenli bir fallback gösterilir.
 */
fun Throwable.toSafeUserMessage(fallback: String): String {
    val raw = message
    val looksRaw = raw == null ||
        raw.length > 160 ||
        raw.contains('\n') ||
        raw.contains("Headers:") ||
        raw.contains("Http Method:")
    if (looksRaw) {
        Log.e("FarketError", fallback, this)
        return fallback
    }
    return raw
}
