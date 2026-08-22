package com.farket.app.ui.messaging

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.farket.app.data.messaging.MessageRow
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.theme.LocalFarketColors

@Composable
fun ConversationDetailScreen(
    viewModel: ConversationDetailViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()
    var draft by remember { mutableStateOf("") }
    var showReportDialog by remember { mutableStateOf(false) }
    var reportReason by remember { mutableStateOf("") }

    if (showReportDialog) {
        AlertDialog(
            onDismissRequest = { showReportDialog = false },
            title = { Text("Kullanıcıyı şikayet et") },
            text = {
                OutlinedTextField(
                    value = reportReason,
                    onValueChange = { reportReason = it },
                    label = { Text("Sebep") },
                )
            },
            confirmButton = {
                TextButton(
                    onClick = { viewModel.report(reportReason); showReportDialog = false; reportReason = "" },
                    enabled = reportReason.isNotBlank(),
                ) { Text("Gönder") }
            },
            dismissButton = { TextButton(onClick = { showReportDialog = false }) { Text("Vazgeç") } },
        )
    }

    val colors = LocalFarketColors.current

    Column(modifier = Modifier.fillMaxSize().padding(20.dp)) {
        Row(horizontalArrangement = Arrangement.SpaceBetween, modifier = Modifier.fillMaxWidth()) {
            Text("@${uiState.otherUsername}", style = MaterialTheme.typography.headlineSmall)
            Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                TextButton(onClick = { showReportDialog = true }, enabled = !uiState.reportSent) { Text("Şikayet Et", color = colors.textSoft) }
                TextButton(onClick = viewModel::block, enabled = !uiState.blocked) { Text("Engelle", color = colors.textSoft) }
            }
        }

        if (uiState.reportSent) {
            Text("Şikayetin gönderildi.", color = colors.correct)
        }
        if (uiState.blocked) {
            Text("Bu kullanıcıyı engelledin.", color = colors.correct)
        }

        if (uiState.errorMessage != null) {
            Text(
                uiState.errorMessage!!,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(top = 4.dp),
            )
        }

        if (uiState.isLoading) {
            CircularProgressIndicator(color = colors.accent, modifier = Modifier.padding(top = 16.dp))
            return@Column
        }

        if (uiState.isRecipient && uiState.isPending) {
            Row(modifier = Modifier.padding(top = 8.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(
                    onClick = viewModel::accept,
                    shape = RoundedCornerShape(14.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
                ) { Text("Kabul Et") }
                OutlinedButton(
                    onClick = viewModel::decline,
                    shape = RoundedCornerShape(14.dp),
                    border = BorderStroke(1.dp, colors.line),
                ) { Text("Reddet") }
            }
        }

        LazyColumn(
            modifier = Modifier.weight(1f).fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            items(uiState.messages, key = { it.id }) { message ->
                MessageBubble(message, isMine = message.senderId == uiState.myUserId)
            }
        }

        if (uiState.canCompose) {
            val limit = uiState.charLimit
            Column(modifier = Modifier.padding(top = 8.dp)) {
                OutlinedTextField(
                    value = draft,
                    onValueChange = { if (limit == null || it.length <= limit) draft = it },
                    label = { Text(if (limit != null) "Mesaj ($limit karakter)" else "Mesaj") },
                    shape = RoundedCornerShape(14.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = colors.accent,
                        unfocusedBorderColor = colors.line,
                        focusedLabelColor = colors.accent,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(
                    modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    if (limit != null) {
                        Text("${draft.length}/$limit", style = MaterialTheme.typography.labelSmall, color = colors.textFaint)
                    }
                    Button(
                        onClick = { viewModel.sendMessage(draft); draft = "" },
                        enabled = draft.isNotBlank() && !uiState.isSending,
                        shape = RoundedCornerShape(14.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
                    ) {
                        Text("Gönder")
                    }
                }
            }
        } else if (uiState.isPending) {
            Text(
                "Karşı taraf kabul etmeli.",
                style = MaterialTheme.typography.bodyMedium,
                color = colors.textSoft,
                modifier = Modifier.padding(top = 8.dp),
            )
        } else if (uiState.isBlocked) {
            Text(
                "Bu kullanıcıyı engelledin, artık mesajlaşamazsınız.",
                style = MaterialTheme.typography.bodyMedium,
                color = colors.textSoft,
                modifier = Modifier.padding(top = 8.dp),
            )
        } else if (uiState.isDeclined) {
            Text(
                "Bu görüşme reddedildi.",
                style = MaterialTheme.typography.bodyMedium,
                color = colors.textSoft,
                modifier = Modifier.padding(top = 8.dp),
            )
        }
    }
}

@Composable
private fun MessageBubble(message: MessageRow, isMine: Boolean) {
    val colors = LocalFarketColors.current

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isMine) Arrangement.End else Arrangement.Start,
    ) {
        Text(
            text = message.body,
            color = if (isMine) colors.accentInk else colors.text,
            style = MaterialTheme.typography.bodyLarge,
            modifier = Modifier
                .widthIn(max = 280.dp)
                .background(if (isMine) colors.accent else colors.veil, RoundedCornerShape(16.dp))
                .padding(horizontal = 14.dp, vertical = 10.dp),
        )
    }
}
