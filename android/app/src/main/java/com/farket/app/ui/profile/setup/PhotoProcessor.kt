package com.farket.app.ui.profile.setup

import android.content.ContentResolver
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import kotlin.math.min

data class ProcessedPhoto(
    val thumbBytes: ByteArray,
    val fullBytes: ByteArray,
    val extension: String,
)

private const val THUMB_MAX_EDGE = 400
private const val FULL_MAX_EDGE = 1600
private const val JPEG_QUALITY = 85

/**
 * Seçilen bir fotoğrafı hem thumb (küçük, kart/liste için) hem full (quiz sırasında büyük
 * gösterim için) sürümüne indirger ve JPEG'e sıkıştırır — Storage'a yüklenecek iki ayrı
 * dosya. RLS policy'si `.jpg` uzantısını kabul ediyor (bkz. proje notları).
 *
 * Decode iki aşamalı: önce inJustDecodeBounds ile yalnızca boyut okunur, sonra
 * inSampleSize ile hedef kenara (1600px) en yakın 2'nin kuvvetine subsample edilerek
 * yüklenir — 50MP bir kamera fotoğrafı tam çözünürlükte (~200MB bitmap) belleğe hiç
 * alınmaz. İşin tamamı Dispatchers.Default'ta çalışır; UI thread'de çağrılmamalı.
 */
object PhotoProcessor {

    // Seçilen URI'ye ait okuma izni bazı cihaz/senaryolarda (ör. picker'ın verdiği geçici
    // grant'ın süresi/kapsamı) SecurityException ile reddedilebiliyor; bu daha önce
    // yakalanmadığı için tüm uygulamayı çökertiyordu. Tek bir fotoğrafın işlenememesi bir
    // kurulum-durdurucu hata değil — çağıran taraf (PhotosStep) zaten null'ları eleyip
    // kalanları yüklüyor, kullanıcı isterse tekrar dener.
    suspend fun process(contentResolver: ContentResolver, uri: Uri): ProcessedPhoto? =
        withContext(Dispatchers.Default) {
            try {
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                val boundsStream = contentResolver.openInputStream(uri)
                if (boundsStream == null) {
                    android.util.Log.e("FarketError", "PhotoProcessor: openInputStream(bounds) NULL for $uri")
                    return@withContext null
                }
                boundsStream.use { BitmapFactory.decodeStream(it, null, bounds) }

                if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
                    android.util.Log.e("FarketError", "PhotoProcessor: bad bounds ${bounds.outWidth}x${bounds.outHeight} for $uri")
                    return@withContext null
                }

                val options = BitmapFactory.Options().apply {
                    inSampleSize = calculateInSampleSize(bounds.outWidth, bounds.outHeight, FULL_MAX_EDGE)
                }
                val original = contentResolver.openInputStream(uri)?.use { stream ->
                    BitmapFactory.decodeStream(stream, null, options)
                }
                if (original == null) {
                    android.util.Log.e("FarketError", "PhotoProcessor: decode(original) NULL for $uri")
                    return@withContext null
                }

                val thumb = scaleDown(original, THUMB_MAX_EDGE)
                val full = scaleDown(original, FULL_MAX_EDGE)

                ProcessedPhoto(
                    thumbBytes = compress(thumb),
                    fullBytes = compress(full),
                    extension = "jpg",
                )
            } catch (e: Exception) {
                android.util.Log.e("FarketError", "PhotoProcessor.process failed for $uri", e)
                null
            }
        }

    private fun calculateInSampleSize(width: Int, height: Int, maxEdge: Int): Int {
        var sampleSize = 1
        var longestEdge = maxOf(width, height)
        // Hedefin altına DÜŞMEYEN en büyük 2'nin kuvveti: son ölçek scaleDown'da yapılır.
        while (longestEdge / 2 >= maxEdge) {
            longestEdge /= 2
            sampleSize *= 2
        }
        return sampleSize
    }

    private fun scaleDown(bitmap: Bitmap, maxEdge: Int): Bitmap {
        val longestEdge = maxOf(bitmap.width, bitmap.height)
        if (longestEdge <= maxEdge) return bitmap
        val scale = maxEdge.toFloat() / longestEdge
        val width = min((bitmap.width * scale).toInt(), bitmap.width)
        val height = min((bitmap.height * scale).toInt(), bitmap.height)
        return Bitmap.createScaledBitmap(bitmap, width.coerceAtLeast(1), height.coerceAtLeast(1), true)
    }

    private fun compress(bitmap: Bitmap): ByteArray =
        ByteArrayOutputStream().use { output ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, output)
            output.toByteArray()
        }
}
