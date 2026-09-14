package com.antigravity.taskcolumn.data.settings

import android.content.Context
import com.antigravity.taskcolumn.TaskColumnApplication
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

enum class AppFontSize(val scale: Float, val label: String) {
    SMALL(0.85f, "小 (85%)"),
    NORMAL(1.0f, "標準 (100%)"),
    LARGE(1.15f, "大 (115%)"),
    EXTRA_LARGE(1.3f, "特大 (130%)")
}

class AppSettingsManager(context: Context = TaskColumnApplication.instance) {
    private val prefs = context.getSharedPreferences("taskcolumn_settings_prefs", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    // Font Scale
    private val _fontScale = MutableStateFlow(loadFontScale())
    val fontScale: StateFlow<Float> = _fontScale.asStateFlow()

    // Smart Filter Order (list of IDs)
    private val defaultOrder = listOf("pending", "today", "upcoming", "all", "completed", "trash")
    private val _smartFilterOrder = MutableStateFlow(loadFilterOrder())
    val smartFilterOrder: StateFlow<List<String>> = _smartFilterOrder.asStateFlow()

    private fun loadFontScale(): Float {
        return prefs.getFloat("app_font_scale", 1.0f)
    }

    fun setFontScale(scale: Float) {
        _fontScale.value = scale
        prefs.edit().putFloat("app_font_scale", scale).apply()
    }

    private fun loadFilterOrder(): List<String> {
        val raw = prefs.getString("smart_filter_order", null)
        if (!raw.isNullOrBlank()) {
            try {
                return json.decodeFromString<List<String>>(raw)
            } catch (_: Exception) {}
        }
        return defaultOrder
    }

    fun setFilterOrder(order: List<String>) {
        _smartFilterOrder.value = order
        try {
            val raw = json.encodeToString(order)
            prefs.edit().putString("smart_filter_order", raw).apply()
        } catch (_: Exception) {}
    }

    fun moveFilterUp(index: Int) {
        if (index <= 0) return
        val current = _smartFilterOrder.value.toMutableList()
        val item = current.removeAt(index)
        current.add(index - 1, item)
        setFilterOrder(current)
    }

    fun moveFilterDown(index: Int) {
        val current = _smartFilterOrder.value.toMutableList()
        if (index >= current.size - 1) return
        val item = current.removeAt(index)
        current.add(index + 1, item)
        setFilterOrder(current)
    }

    fun resetFilterOrder() {
        setFilterOrder(defaultOrder)
    }

    companion object {
        val shared by lazy { AppSettingsManager() }
    }
}
