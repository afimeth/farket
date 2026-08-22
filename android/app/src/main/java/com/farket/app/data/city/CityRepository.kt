package com.farket.app.data.city

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Columns
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.postgrest.rpc

class CityRepository(
    private val supabase: SupabaseClient,
) {
    suspend fun listCities(): List<CityRow> =
        supabase.postgrest.from("cities")
            .select(columns = Columns.list("id", "name")) {
                filter { eq("is_active", true) }
                order("name", Order.ASCENDING)
            }
            .decodeList()

    /**
     * `set_city` 24 saat kuralı ihlalinde şu sabit hatayı fırlatır (bkz. proje notları):
     * 'Şehir değişikliği için 24 saat beklemelisin (son değişim: %)'. Kalan süre yapılandırılmış
     * bir alan olarak dönmüyor — hata mesajı olduğu gibi kullanıcıya gösteriliyor.
     */
    suspend fun setCity(cityId: Int): Result<SetCityResult> = runCatching {
        supabase.postgrest.rpc(
            function = "set_city",
            parameters = SetCityParams(cityId = cityId),
        ).decodeAs()
    }
}
