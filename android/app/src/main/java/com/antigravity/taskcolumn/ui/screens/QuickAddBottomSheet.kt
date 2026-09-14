package com.antigravity.taskcolumn.ui.screens

import android.app.TimePickerDialog
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.taskcolumn.ui.theme.AccentBlue
import com.antigravity.taskcolumn.ui.theme.CalendarTeal
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickAddBottomSheet(
    onDismiss: () -> Unit,
    onAddTask: (title: String, notes: String?, due: Long?) -> Unit
) {
    val context = LocalContext.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var title by remember { mutableStateOf("") }
    var selectedDueMode by remember { mutableStateOf(0) } // 0: None, 1: Today, 2: Tomorrow, 3: Custom
    var customDueTimestamp by remember { mutableStateOf<Long?>(null) }
    var showDatePicker by remember { mutableStateOf(false) }

    val focusRequester = remember { FocusRequester() }

    val customDateStr = remember(customDueTimestamp) {
        customDueTimestamp?.let {
            SimpleDateFormat("M月d日 HH:mm", Locale.getDefault()).format(Date(it))
        }
    }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 16.dp, topEnd = 16.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp, vertical = 12.dp)
                .imePadding()
        ) {
            TextField(
                value = title,
                onValueChange = { title = it },
                placeholder = { Text("新增待辦事項...", fontSize = 16.sp) },
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .focusRequester(focusRequester)
            )

            LaunchedEffect(Unit) {
                focusRequester.requestFocus()
            }

            Spacer(modifier = Modifier.height(12.dp))

            // Quick Due Chips & Send Button
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Row(
                    modifier = Modifier
                        .weight(1f)
                        .horizontalScroll(rememberScrollState()),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    FilterChip(
                        selected = selectedDueMode == 1,
                        onClick = {
                            if (selectedDueMode == 1) {
                                selectedDueMode = 0
                            } else {
                                selectedDueMode = 1
                                customDueTimestamp = null
                            }
                        },
                        label = { Text("今天", fontSize = 12.sp) }
                    )

                    FilterChip(
                        selected = selectedDueMode == 2,
                        onClick = {
                            if (selectedDueMode == 2) {
                                selectedDueMode = 0
                            } else {
                                selectedDueMode = 2
                                customDueTimestamp = null
                            }
                        },
                        label = { Text("明天", fontSize = 12.sp) }
                    )

                    FilterChip(
                        selected = selectedDueMode == 3,
                        onClick = {
                            if (selectedDueMode == 3 && customDueTimestamp != null) {
                                selectedDueMode = 0
                                customDueTimestamp = null
                            } else {
                                showDatePicker = true
                            }
                        },
                        leadingIcon = {
                            Icon(
                                imageVector = Icons.Default.CalendarMonth,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = if (selectedDueMode == 3) AccentBlue else CalendarTeal
                            )
                        },
                        trailingIcon = {
                            if (selectedDueMode == 3 && customDueTimestamp != null) {
                                IconButton(
                                    onClick = {
                                        selectedDueMode = 0
                                        customDueTimestamp = null
                                    },
                                    modifier = Modifier.size(16.dp)
                                ) {
                                    Icon(imageVector = Icons.Default.Close, contentDescription = "清除", modifier = Modifier.size(14.dp))
                                }
                            }
                        },
                        label = {
                            Text(
                                text = customDateStr ?: "自訂日期與時間",
                                fontSize = 12.sp
                            )
                        }
                    )
                }

                Spacer(modifier = Modifier.width(8.dp))

                IconButton(
                    onClick = {
                        val trimmed = title.trim()
                        if (trimmed.isNotEmpty()) {
                            val dueTimestamp = when (selectedDueMode) {
                                1 -> Calendar.getInstance().timeInMillis
                                2 -> Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }.timeInMillis
                                3 -> customDueTimestamp
                                else -> null
                            }
                            onAddTask(trimmed, null, dueTimestamp)
                        }
                    },
                    enabled = title.isNotBlank()
                ) {
                    Icon(
                        imageVector = Icons.Default.Send,
                        contentDescription = "送出",
                        tint = if (title.isNotBlank()) AccentBlue else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)
                    )
                }
            }

            Spacer(modifier = Modifier.height(24.dp))
        }
    }

    // Material 3 Date Picker Dialog
    if (showDatePicker) {
        val datePickerState = rememberDatePickerState(
            initialSelectedDateMillis = customDueTimestamp ?: System.currentTimeMillis()
        )
        DatePickerDialog(
            onDismissRequest = { showDatePicker = false },
            confirmButton = {
                TextButton(
                    onClick = {
                        showDatePicker = false
                        val selectedDateMillis = datePickerState.selectedDateMillis
                        if (selectedDateMillis != null) {
                            val cal = Calendar.getInstance().apply {
                                timeInMillis = selectedDateMillis
                            }
                            val currentHour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
                            val currentMin = Calendar.getInstance().get(Calendar.MINUTE)

                            TimePickerDialog(
                                context,
                                { _, hourOfDay, minute ->
                                    cal.set(Calendar.HOUR_OF_DAY, hourOfDay)
                                    cal.set(Calendar.MINUTE, minute)
                                    cal.set(Calendar.SECOND, 0)
                                    customDueTimestamp = cal.timeInMillis
                                    selectedDueMode = 3
                                },
                                currentHour,
                                currentMin,
                                true
                            ).show()
                        }
                    }
                ) {
                    Text("下一步 (選擇時間)")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDatePicker = false }) {
                    Text("取消")
                }
            }
        ) {
            DatePicker(state = datePickerState)
        }
    }
}
