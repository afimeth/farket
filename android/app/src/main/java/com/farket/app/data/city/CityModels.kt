package com.farket.app.data.city

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class CityRow(
    val id: Int,
    val name: String,
)

@Serializable
internal data class SetCityParams(
    @SerialName("p_city_id") val cityId: Int,
)

@Serializable
data class SetCityResult(
    @SerialName("city_id") val cityId: Int,
    val changed: Boolean,
)
