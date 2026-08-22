package com.farket.app.ui.profile.setup

import androidx.compose.foundation.border
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.scale
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.DatePicker
import androidx.compose.material3.DatePickerDialog
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.SelectableDates
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberDatePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.farket.app.data.profile.CityRow
import com.farket.app.data.profile.IdentityAttributeDraft
import com.farket.app.data.profile.IdentityAttributeRow
import com.farket.app.data.profile.PublishProfileResult
import com.farket.app.ui.theme.LocalFarketColors

@Composable
internal fun BasicInfoStep(
    uiState: ProfileSetupUiState,
    onSubmit: (displayName: String, birthDate: String, sex: String, cityId: Int) -> Unit,
) {
    val colors = LocalFarketColors.current
    var displayName by remember { mutableStateOf("") }
    // Elle yazım (GG-AA-YYYY) kullanıcı testinde kafa karıştırıcı bulundu —
    // takvimden seçim daha az hataya açık. Geçersiz/gelecek tarih artık
    // seçilemiyor bile (SelectableDates), backend'e ham hata sızma riski kalmadı.
    var birthDate by remember { mutableStateOf<java.time.LocalDate?>(null) }
    var showDatePicker by remember { mutableStateOf(false) }
    var sex by remember { mutableStateOf<String?>(null) }
    var selectedCity by remember { mutableStateOf<CityRow?>(null) }

    Text("Temel bilgiler", style = MaterialTheme.typography.headlineSmall)
    OutlinedTextField(
        value = displayName,
        onValueChange = { displayName = it },
        label = { Text("Adın") },
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.line,
            focusedLabelColor = colors.accent,
        ),
        modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
    )
    OutlinedTextField(
        value = birthDate?.format(BIRTH_DATE_FORMATTER) ?: "",
        onValueChange = {},
        readOnly = true,
        enabled = false,
        label = { Text("Doğum tarihi") },
        trailingIcon = { Icon(Icons.Filled.DateRange, contentDescription = null, tint = colors.textSoft) },
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            disabledBorderColor = colors.line,
            disabledTextColor = colors.text,
            disabledLabelColor = colors.textSoft,
            disabledTrailingIconColor = colors.textSoft,
        ),
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp)
            .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null) {
                showDatePicker = true
            },
    )

    if (showDatePicker) {
        BirthDatePickerDialog(
            initial = birthDate,
            onDismiss = { showDatePicker = false },
            onConfirm = { picked -> birthDate = picked; showDatePicker = false },
        )
    }

    Text("Cinsiyet", style = MaterialTheme.typography.labelLarge, color = colors.textSoft, modifier = Modifier.padding(top = 16.dp))
    Row {
        listOf("female" to "Kadın", "male" to "Erkek", "other" to "Diğer").forEach { (value, label) ->
            Row {
                RadioButton(
                    selected = sex == value,
                    onClick = { sex = value },
                    colors = RadioButtonDefaults.colors(selectedColor = colors.accent),
                )
                Text(label, modifier = Modifier.padding(top = 12.dp, end = 12.dp))
            }
        }
    }

    CityDropdown(cities = uiState.cities, selected = selectedCity, onSelect = { selectedCity = it })

    // Eksik alanları tek tek sayıyoruz: "bir şeyler eksik" demek yerine hangisinin
    // eksik olduğunu söylemek gerekiyor.
    val missingBasics = listOfNotNull(
        "adın".takeIf { displayName.isBlank() },
        "doğum tarihin".takeIf { birthDate == null },
        "cinsiyetin".takeIf { sex == null },
        "şehrin".takeIf { selectedCity == null },
    )

    StepActions(
        label = "İleri",
        enabled = missingBasics.isEmpty(),
        onClick = { onSubmit(displayName, birthDate!!.toString(), sex!!, selectedCity!!.id) },
        blockedReason = "Eksik: ${missingBasics.joinToString(", ")}.",
    )
}

private val BIRTH_DATE_FORMATTER = java.time.format.DateTimeFormatter.ofPattern("dd-MM-yyyy")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BirthDatePickerDialog(
    initial: java.time.LocalDate?,
    onDismiss: () -> Unit,
    onConfirm: (java.time.LocalDate) -> Unit,
) {
    val colors = LocalFarketColors.current
    val zone = java.time.ZoneOffset.UTC
    val todayMillis = java.time.LocalDate.now().atStartOfDay(zone).toInstant().toEpochMilli()
    val state = rememberDatePickerState(
        initialSelectedDateMillis = (initial ?: java.time.LocalDate.now().minusYears(20))
            .atStartOfDay(zone).toInstant().toEpochMilli(),
        selectableDates = object : SelectableDates {
            // Gelecek bir tarih doğum günü olamaz — seçim aşamasında engelleniyor.
            override fun isSelectableDate(utcTimeMillis: Long) = utcTimeMillis <= todayMillis
        },
    )

    DatePickerDialog(
        onDismissRequest = onDismiss,
        confirmButton = {
            TextButton(
                onClick = {
                    state.selectedDateMillis?.let { millis ->
                        onConfirm(java.time.Instant.ofEpochMilli(millis).atZone(zone).toLocalDate())
                    }
                },
            ) { Text("Tamam", color = colors.accent) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Vazgeç", color = colors.textSoft) }
        },
    ) {
        DatePicker(state = state)
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun CityDropdown(cities: List<CityRow>, selected: CityRow?, onSelect: (CityRow) -> Unit) {
    val colors = LocalFarketColors.current
    var expanded by remember { mutableStateOf(false) }
    var query by remember(selected) { mutableStateOf(selected?.name ?: "") }
    val filteredCities = remember(cities, query) {
        if (query.isBlank()) cities else cities.filter { it.name.contains(query, ignoreCase = true) }
    }

    ExposedDropdownMenuBox(
        expanded = expanded,
        onExpandedChange = { expanded = it },
        modifier = Modifier.padding(top = 16.dp),
    ) {
        OutlinedTextField(
            value = query,
            onValueChange = { query = it; expanded = true },
            label = { Text("Şehir ara") },
            trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
            shape = RoundedCornerShape(14.dp),
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = colors.accent,
                unfocusedBorderColor = colors.line,
                focusedLabelColor = colors.accent,
            ),
            modifier = Modifier.fillMaxWidth().menuAnchor(),
        )
        ExposedDropdownMenu(
            expanded = expanded && filteredCities.isNotEmpty(),
            onDismissRequest = { expanded = false },
            containerColor = colors.surface,
        ) {
            filteredCities.forEach { city ->
                DropdownMenuItem(
                    text = { Text(city.name) },
                    onClick = {
                        onSelect(city)
                        expanded = false
                    },
                )
            }
        }
    }
}

@Composable
internal fun AgeAttestationStep(onConfirm: () -> Unit) {
    val colors = LocalFarketColors.current
    var checked by remember { mutableStateOf(false) }

    Text("18 yaş beyanı", style = MaterialTheme.typography.headlineSmall)
    Row(modifier = Modifier.padding(top = 16.dp)) {
        Checkbox(
            checked = checked,
            onCheckedChange = { checked = it },
            colors = CheckboxDefaults.colors(checkedColor = colors.accent, checkmarkColor = colors.accentInk),
        )
        Text(
            "18 yaşından büyüğüm.",
            modifier = Modifier.padding(top = 12.dp),
        )
    }
    StepActions(
        label = "İleri",
        enabled = checked,
        onClick = onConfirm,
        blockedReason = "Devam etmek için 18 yaşından büyük olduğunu işaretlemen gerekiyor.",
    )
}

private val USERNAME_REGEX = Regex("^[a-z0-9_]{3,20}$")

@Composable
internal fun UsernameStep(onSubmit: (String) -> Unit) {
    val colors = LocalFarketColors.current
    var username by remember { mutableStateOf("") }
    val isValid = USERNAME_REGEX.matches(username)

    Text("Kullanıcı adı", style = MaterialTheme.typography.headlineSmall)
    OutlinedTextField(
        value = username,
        onValueChange = { username = it.lowercase() },
        label = { Text("@handle") },
        supportingText = { Text("3-20 karakter, yalnızca a-z 0-9 _") },
        isError = username.isNotEmpty() && !isValid,
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.line,
            focusedLabelColor = colors.accent,
        ),
        modifier = Modifier.fillMaxWidth().padding(top = 16.dp),
    )
    StepActions(
        label = "İleri",
        enabled = isValid,
        onClick = { onSubmit(username) },
        blockedReason = if (username.isBlank()) {
            "Devam etmek için bir kullanıcı adı seç."
        } else {
            "Kullanıcı adı 3-20 karakter olmalı ve yalnızca a-z, 0-9 ve _ içerebilir."
        },
    )
}

@Composable
internal fun IdentityCardStep(
    onSubmit: (
        showName: Boolean, showAge: Boolean, showOccupation: Boolean,
        showCity: Boolean, showIntent: Boolean, occupation: String?, intent: String,
    ) -> Unit,
) {
    val colors = LocalFarketColors.current
    var showName by remember { mutableStateOf(true) }
    var showAge by remember { mutableStateOf(true) }
    var showOccupation by remember { mutableStateOf(true) }
    var showCity by remember { mutableStateOf(true) }
    var showIntent by remember { mutableStateOf(true) }
    var occupation by remember { mutableStateOf("") }
    var intent by remember { mutableStateOf("arkadaslik") }

    Text("Künye", style = MaterialTheme.typography.headlineSmall)
    Text(
        "Quiz'i geçenlere hangi bilgilerin açılacağını sen seçersin.",
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.padding(top = 4.dp, bottom = 16.dp),
    )

    ToggleRow("İsim", showName) { showName = it }
    ToggleRow("Yaş", showAge) { showAge = it }
    ToggleRow("Meslek", showOccupation) { showOccupation = it }
    ToggleRow("Şehir", showCity) { showCity = it }
    ToggleRow("Aradığın", showIntent) { showIntent = it }

    OutlinedTextField(
        value = occupation,
        onValueChange = { occupation = it },
        label = { Text("Meslek") },
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = colors.accent,
            unfocusedBorderColor = colors.line,
            focusedLabelColor = colors.accent,
        ),
        modifier = Modifier.fillMaxWidth().padding(top = 12.dp),
    )

    Text("Ne arıyorsun?", style = MaterialTheme.typography.labelLarge, color = colors.textSoft, modifier = Modifier.padding(top = 16.dp))
    Row {
        listOf("arkadaslik" to "Arkadaşlık", "flort" to "Flört").forEach { (value, label) ->
            Row {
                RadioButton(
                    selected = intent == value,
                    onClick = { intent = value },
                    colors = RadioButtonDefaults.colors(selectedColor = colors.accent),
                )
                Text(label, modifier = Modifier.padding(top = 12.dp, end = 12.dp))
            }
        }
    }

    StepActions(
        label = "İleri",
        enabled = true,
        onClick = {
            onSubmit(showName, showAge, showOccupation, showCity, showIntent, occupation.ifBlank { null }, intent)
        },
    )
}

@Composable
internal fun ToggleRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    val colors = LocalFarketColors.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, modifier = Modifier.padding(top = 12.dp))
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(checkedThumbColor = colors.accentInk, checkedTrackColor = colors.accent),
        )
    }
}

internal data class AttributeFieldSpec(val type: String, val label: String, val isNumeric: Boolean)

internal val IDENTITY_ATTRIBUTE_FIELD_SPECS = listOf(
    AttributeFieldSpec("school", "Okul", isNumeric = false),
    AttributeFieldSpec("job", "Meslek", isNumeric = false),
    AttributeFieldSpec("hometown", "Memleket", isNumeric = false),
    AttributeFieldSpec("height_cm", "Boy (cm)", isNumeric = true),
    AttributeFieldSpec("weight_kg", "Kilo (kg)", isNumeric = true),
)

/**
 * `profile_identity_attributes` yalnızca `height_cm`/`weight_kg`/`age` için quiz-eligible
 * işaretlemeye izin veriyor (bkz. migration CHECK kısıtı); `age` sunucu tarafından
 * `reveal_identity`'de türetildiği için buradaki sabit alan setine dahil edilmiyor —
 * kullanıcı yalnızca boy/kilo'yu quiz için işaretleyebilir.
 */
@Stable
internal class IdentityAttributesState(initial: Map<String, IdentityAttributeRow>) {
    val values = mutableStateMapOf<String, String>().apply {
        IDENTITY_ATTRIBUTE_FIELD_SPECS.forEach { spec ->
            val row = initial[spec.type]
            val text = if (spec.isNumeric) {
                row?.valueNumeric?.let { if (it == it.toLong().toDouble()) it.toLong().toString() else it.toString() } ?: ""
            } else {
                row?.valueText ?: ""
            }
            put(spec.type, text)
        }
    }
    val shown = mutableStateMapOf<String, Boolean>().apply {
        IDENTITY_ATTRIBUTE_FIELD_SPECS.forEach { spec -> put(spec.type, initial[spec.type]?.isShownOnReveal ?: false) }
    }
    val quizEligible = mutableStateMapOf<String, Boolean>().apply {
        IDENTITY_ATTRIBUTE_FIELD_SPECS.forEach { spec -> put(spec.type, initial[spec.type]?.isQuizEligible ?: false) }
    }

    val hasQuizEligibleFilled: Boolean
        get() = IDENTITY_ATTRIBUTE_FIELD_SPECS.filter { it.isNumeric }.any { spec ->
            quizEligible[spec.type] == true && values[spec.type]?.toDoubleOrNull() != null
        }

    fun drafts(): List<IdentityAttributeDraft> = IDENTITY_ATTRIBUTE_FIELD_SPECS.mapNotNull { spec ->
        val raw = values[spec.type]?.trim().orEmpty()
        if (raw.isBlank()) return@mapNotNull null
        if (spec.isNumeric) {
            val numeric = raw.toDoubleOrNull() ?: return@mapNotNull null
            IdentityAttributeDraft(
                attributeType = spec.type,
                valueNumeric = numeric,
                isShownOnReveal = shown[spec.type] == true,
                isQuizEligible = quizEligible[spec.type] == true,
            )
        } else {
            IdentityAttributeDraft(
                attributeType = spec.type,
                valueText = raw,
                isShownOnReveal = shown[spec.type] == true,
                isQuizEligible = false,
            )
        }
    }
}

@Composable
internal fun rememberIdentityAttributesState(initial: List<IdentityAttributeRow>): IdentityAttributesState {
    val byType = remember(initial) { initial.associateBy { it.attributeType } }
    return remember(byType) { IdentityAttributesState(byType) }
}

@Composable
@OptIn(ExperimentalLayoutApi::class)
internal fun IdentityAttributesFields(state: IdentityAttributesState) {
    val colors = LocalFarketColors.current

    // Alanlar tam genişlik yığın yerine akışkan düzende: her alan kendi kartında,
    // satıra sığdığı kadarı yan yana, sığmayan alt satıra geçiyor. Eskiden beş alan
    // + anahtarları ekranı gereksiz uzatıyor ve ayarlar sayfasını dolduruyordu.
    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        IDENTITY_ATTRIBUTE_FIELD_SPECS.forEach { spec ->
            Column(
                modifier = Modifier
                    .fillMaxWidth(0.48f)
                    .border(1.dp, colors.line, RoundedCornerShape(14.dp))
                    .padding(10.dp),
            ) {
                OutlinedTextField(
                    value = state.values[spec.type] ?: "",
                    onValueChange = { state.values[spec.type] = it },
                    label = { Text(spec.label, style = MaterialTheme.typography.labelSmall) },
                    singleLine = true,
                    keyboardOptions = if (spec.isNumeric) {
                        KeyboardOptions(keyboardType = KeyboardType.Number)
                    } else {
                        KeyboardOptions.Default
                    },
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = colors.accent,
                        unfocusedBorderColor = colors.line,
                        focusedLabelColor = colors.accent,
                    ),
                    modifier = Modifier.fillMaxWidth(),
                )
                CompactToggle("Künyede göster", state.shown[spec.type] == true) { state.shown[spec.type] = it }
                if (spec.isNumeric) {
                    CompactToggle("Quiz için kullan", state.quizEligible[spec.type] == true) {
                        state.quizEligible[spec.type] = it
                    }
                }
            }
        }
    }
}

/** Dar hücrelere sığsın diye küçük etiketli, kompakt anahtar satırı. */
@Composable
private fun CompactToggle(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    val colors = LocalFarketColors.current
    Row(
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = colors.textSoft,
            modifier = Modifier.weight(1f).padding(end = 4.dp),
        )
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(checkedThumbColor = colors.accentInk, checkedTrackColor = colors.accent),
            modifier = Modifier.scale(0.75f),
        )
    }
}

@Composable
internal fun IdentityAttributesStep(
    initial: List<IdentityAttributeRow>,
    onSubmit: (List<IdentityAttributeDraft>) -> Unit,
) {
    val state = rememberIdentityAttributesState(initial)

    Text("Künye bilgileri", style = MaterialTheme.typography.headlineSmall)
    Text(
        "Okul, meslek, memleket, boy, kilo gibi ek bilgiler ekle. Boy veya kilodan en az " +
            "birini quiz için işaretlemen gerekiyor — profilini bu olmadan yayınlayamazsın.",
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.padding(top = 4.dp, bottom = 8.dp),
    )

    IdentityAttributesFields(state)

    StepActions(
        label = "İleri",
        enabled = state.hasQuizEligibleFilled,
        onClick = { onSubmit(state.drafts()) },
        blockedReason = "Devam etmek için boy ya da kilodan birini yaz ve o alanın " +
            "\"Quiz için kullan\" anahtarını aç. Quiz soruların bu bilgiden üretiliyor.",
    )
}

@Composable
internal fun PublishStep(uiState: ProfileSetupUiState, onPublish: () -> Unit) {
    Text("Yayınla", style = MaterialTheme.typography.headlineSmall)
    Text(
        "Her şey hazır. Profilini yayınlamak için aşağıya dokun.",
        style = MaterialTheme.typography.bodyMedium,
        modifier = Modifier.padding(top = 8.dp, bottom = 8.dp),
    )

    val result: PublishProfileResult? = uiState.publishResult
    if (result != null && result.status != "published") {
        Text(result.status, modifier = Modifier.padding(bottom = 8.dp))
    }

    StepActions(label = "Yayınla", enabled = true, onClick = onPublish)
}
