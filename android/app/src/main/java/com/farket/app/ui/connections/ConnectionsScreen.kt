package com.farket.app.ui.connections

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.farket.app.data.connections.ConnectionRow
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.common.EmptyState
import com.farket.app.ui.theme.LocalFarketColors

/**
 * Bağlantılarım.
 *
 * "Arkadaşlarım" değil bilerek: bir bağlantı quiz çözmekle ya da ilk etabı geçmekle
 * kurulmuyor — yalnızca iki tarafın da mesaj atmasıyla kuruluyor. Liste doğrudan
 * `get_my_connections`'tan geliyor, bu kural orada tanımlı.
 */
@Composable
fun ConnectionsScreen(
    onOpenConversation: (conversationId: String) -> Unit,
    viewModel: ConnectionsViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()
    val colors = LocalFarketColors.current
    var pendingRemoval by remember { mutableStateOf<ConnectionRow?>(null) }

    // Geri alınamaz bir işlem: sonucu taahhütten önce, tam olarak yazıyoruz.
    pendingRemoval?.let { target ->
        AlertDialog(
            onDismissRequest = { pendingRemoval = null },
            title = { Text("Bağlantıdan çıkar") },
            text = {
                Text(
                    "@${target.username ?: "?"} ile bağlantını sonlandırmak üzeresin.\n\n" +
                        "• Sohbetiniz kapanır, birbirinize mesaj gönderemezsiniz.\n" +
                        "• Bu işlem geri alınamaz.\n" +
                        "• Yeniden mesajlaşabilmek için ikinizin de birbirinizin quizini " +
                        "baştan çözmesi gerekir.\n\nDevam etmek istiyor musun?",
                )
            },
            confirmButton = {
                TextButton(
                    onClick = { viewModel.removeConnection(target.profileId); pendingRemoval = null },
                    enabled = !uiState.isRemoving,
                ) {
                    Text("Bağlantıdan çıkar", color = MaterialTheme.colorScheme.error)
                }
            },
            dismissButton = { TextButton(onClick = { pendingRemoval = null }) { Text("Vazgeç") } },
        )
    }

    Column(modifier = Modifier.fillMaxSize().padding(20.dp)) {
        Text("Bağlantılarım", style = MaterialTheme.typography.headlineSmall)
        Text(
            "Karşılıklı mesajlaştığın kişiler. Biri sana yazdı, sen de ona yazdıysan " +
                "bağlantı kurulmuş sayılır.",
            style = MaterialTheme.typography.bodySmall,
            color = colors.textSoft,
            modifier = Modifier.padding(top = 6.dp, bottom = 16.dp),
        )

        if (uiState.errorMessage != null) {
            Text(
                uiState.errorMessage!!,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(bottom = 8.dp),
            )
        }
        if (uiState.message != null) {
            Text(uiState.message!!, color = colors.correct, modifier = Modifier.padding(bottom = 8.dp))
        }

        if (uiState.isLoading) {
            CircularProgressIndicator(color = colors.accent)
        } else if (uiState.connections.isEmpty()) {
            EmptyState("Henüz bağlantın yok.")
            Text(
                "Bir quizi geçip mesaj gönder; karşı taraf da sana yazdığında burada görünür.",
                style = MaterialTheme.typography.bodySmall,
                color = colors.textSoft,
                modifier = Modifier.padding(top = 8.dp),
            )
        } else {
            LazyColumn {
                items(uiState.connections, key = { it.profileId }) { connection ->
                    ConnectionRowItem(
                        connection = connection,
                        onClick = { onOpenConversation(connection.conversationId) },
                        onRemove = { pendingRemoval = connection },
                    )
                    HorizontalDivider(color = colors.line)
                }
            }
        }
    }
}

@Composable
private fun ConnectionRowItem(
    connection: ConnectionRow,
    onClick: () -> Unit,
    onRemove: () -> Unit,
) {
    val colors = LocalFarketColors.current

    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(
            modifier = Modifier.weight(1f).clickable(onClick = onClick).padding(vertical = 6.dp, horizontal = 2.dp),
        ) {
            Text("@${connection.username ?: "?"}", style = MaterialTheme.typography.titleMedium)
            val since = formatDay(connection.connectedAt)
            if (since != null) {
                Text(
                    "$since tarihinden beri bağlantınız var",
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.textSoft,
                    modifier = Modifier.padding(top = 4.dp),
                )
            }
        }
        Text(
            text = formatDay(connection.lastMessageAt) ?: "",
            style = MaterialTheme.typography.labelMedium,
            color = colors.textFaint,
            modifier = Modifier.padding(end = 4.dp),
        )
        TextButton(onClick = onRemove) {
            Text("Çıkar", style = MaterialTheme.typography.bodySmall, color = colors.textSoft)
        }
    }
}

private fun formatDay(iso: String?): String? = iso?.let {
    runCatching {
        java.time.OffsetDateTime.parse(it)
            .atZoneSameInstant(java.time.ZoneId.of("Europe/Istanbul"))
            .format(java.time.format.DateTimeFormatter.ofPattern("d MMM", java.util.Locale("tr")))
    }.getOrNull()
}
