package com.farket.app.ui.common

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Info
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.farket.app.ui.theme.LocalFarketColors

/** Boş liste durumlarında (Mesajlar/Bildirimler/Engellenenler/vb.) ortak, ikonlu görünüm. */
@Composable
fun EmptyState(message: String, modifier: Modifier = Modifier) {
    val colors = LocalFarketColors.current
    Column(
        modifier = modifier.fillMaxWidth().padding(vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            imageVector = Icons.Filled.Info,
            contentDescription = null,
            tint = colors.textFaint,
            modifier = Modifier.padding(bottom = 8.dp),
        )
        Text(message, color = colors.textSoft, style = MaterialTheme.typography.bodyMedium)
    }
}
