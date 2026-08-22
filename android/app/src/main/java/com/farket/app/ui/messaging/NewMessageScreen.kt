package com.farket.app.ui.messaging

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.theme.LocalFarketColors

/** İlk mesaj gönderme — henüz bir `conversation` yok, `send_message` bunu oluşturur. */
@Composable
fun NewMessageScreen(
    onSent: (conversationId: String) -> Unit,
    viewModel: NewMessageViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()
    var draft by remember { mutableStateOf("") }
    val limit = viewModel.optimisticCharLimit

    LaunchedEffect(uiState.createdConversationId) {
        uiState.createdConversationId?.let { onSent(it) }
    }

    val colors = LocalFarketColors.current

    Column(modifier = Modifier.fillMaxSize().padding(20.dp)) {
        Text("Mesaj gönder", style = MaterialTheme.typography.headlineSmall)

        if (uiState.errorMessage != null) {
            Text(
                uiState.errorMessage!!,
                color = MaterialTheme.colorScheme.error,
                modifier = Modifier.padding(top = 8.dp),
            )
        }

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
            modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
        )

        Row(modifier = Modifier.fillMaxWidth().padding(top = 4.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            if (limit != null) {
                Text("${draft.length}/$limit", style = MaterialTheme.typography.labelSmall, color = colors.textFaint)
            }
            Button(
                onClick = { viewModel.send(draft) },
                enabled = draft.isNotBlank() && !uiState.isSending,
                shape = RoundedCornerShape(14.dp),
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = colors.accentInk),
            ) {
                Text("Gönder")
            }
        }
    }
}
