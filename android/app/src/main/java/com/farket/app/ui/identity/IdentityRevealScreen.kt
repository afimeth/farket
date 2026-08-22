package com.farket.app.ui.identity

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
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
import com.farket.app.data.identity.IDENTITY_ATTRIBUTE_LABELS
import com.farket.app.data.identity.IdentityRevealResult
import com.farket.app.ui.FarketViewModelFactory
import com.farket.app.ui.theme.LocalFarketColors

/**
 * Künye açma — bkz. proje notları FARKET_PROMPTLAR.md Prompt 6. Gelen alanlar sabit bir form
 * değil, dinamik olarak (hangi alan geldiyse yalnızca o) render edilir.
 */
@Composable
fun IdentityRevealScreen(
    viewModel: IdentityViewModel = viewModel(factory = FarketViewModelFactory),
) {
    val uiState by viewModel.uiState.collectAsState()

    val colors = LocalFarketColors.current

    Column(modifier = Modifier.fillMaxSize().padding(20.dp)) {
        Text("Künye", style = MaterialTheme.typography.headlineSmall, modifier = Modifier.padding(bottom = 16.dp))

        when (val state = uiState) {
            is IdentityUiState.Loading -> CircularProgressIndicator(color = colors.accent)
            is IdentityUiState.Error -> {
                Text(state.message, color = MaterialTheme.colorScheme.error)
            }
            is IdentityUiState.Success -> {
                if (state.result.hasAnyField) {
                    IdentityFields(state.result)
                } else {
                    Text("Bu kişi künye bilgisi paylaşmıyor.", color = colors.textSoft)
                }
            }
        }
    }
}

@Composable
private fun IdentityFields(result: IdentityRevealResult) {
    result.attributes.forEach { (attributeType, value) ->
        IdentityRow(IDENTITY_ATTRIBUTE_LABELS[attributeType] ?: attributeType, value)
    }
}

@Composable
private fun IdentityRow(label: String, value: String) {
    val colors = LocalFarketColors.current
    Column(modifier = Modifier.padding(vertical = 10.dp)) {
        Text(label, style = MaterialTheme.typography.labelMedium)
        Text(value, style = MaterialTheme.typography.bodyLarge, modifier = Modifier.padding(top = 2.dp))
    }
    HorizontalDivider(color = colors.line)
}
