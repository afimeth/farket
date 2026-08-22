package com.farket.app.data.connections

import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.rpc

/**
 * `profiles` üzerindeki tek select politikası "yalnızca kendi profilin" olduğu için
 * karşı tarafın username'i doğrudan okunamıyor; get_blocked_users / get_my_connections
 * ile aynı desen: SECURITY DEFINER bir RPC yalnızca çağıranın kendi sohbetlerini okuyup
 * karşı tarafın görünen bilgisini döndürüyor.
 */
class ConnectionsRepository(
    private val supabase: SupabaseClient,
) {
    suspend fun listConnections(): Result<List<ConnectionRow>> = runCatching {
        supabase.postgrest.rpc(function = "get_my_connections").decodeList()
    }

    /**
     * Bağlantıyı sonlandırır. GERİ ALINAMAZ: sohbet kapanır ve taraflar yeniden
     * mesajlaşmak için birbirlerinin quizini baştan çözmek zorunda kalır. Çağırmadan
     * önce kullanıcıya onay diyaloğu gösterilmeli.
     */
    suspend fun removeConnection(profileId: String): Result<Unit> = runCatching {
        supabase.postgrest.rpc(
            function = "remove_connection",
            parameters = RemoveConnectionParams(profileId = profileId),
        )
        Unit
    }
}
