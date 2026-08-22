package com.farket.app.ui.messaging

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.farket.app.data.messaging.ConversationSummary
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.common.EmptyState
import com.farket.app.ui.theme.LocalFarketColors

@Composable
fun ConversationListScreen(
    onOpenConversation: (conversationId: String) -> Unit,
    viewModel: ConversationListViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()
    val colors = LocalFarketColors.current

    Column(modifier = Modifier.fillMaxSize().padding(20.dp)) {
        Text("Mesajlar", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(bottom = 16.dp))

        if (uiState.errorMessage != null) {
            Text(uiState.errorMessage!!, color = MaterialTheme.colorScheme.error)
        }

        if (uiState.isLoading) {
            CircularProgressIndicator(color = colors.accent)
        } else if (uiState.conversations.isEmpty()) {
            EmptyState("Henüz bir konuşman yok.")
        } else {
            LazyColumn {
                items(uiState.conversations, key = { it.conversation.id }) { summary ->
                    ConversationRow(summary, onClick = { onOpenConversation(summary.conversation.id) })
                    HorizontalDivider(color = colors.line)
                }
            }
        }
    }
}

@Composable
private fun ConversationRow(summary: ConversationSummary, onClick: () -> Unit) {
    val colors = LocalFarketColors.current

    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column {
            Text("@${summary.otherUsername}", style = MaterialTheme.typography.titleMedium)
            Text(
                text = summary.lastMessageBody ?: "Henüz mesaj yok",
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.padding(top = 4.dp),
            )
        }
        Text(
            text = if (summary.conversation.status == "accepted") "aktif" else "bekliyor",
            style = MaterialTheme.typography.labelMedium,
            color = if (summary.conversation.status == "accepted") colors.correct else colors.textFaint,
        )
    }
}
