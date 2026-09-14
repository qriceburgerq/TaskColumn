package com.antigravity.taskcolumn.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Send
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.taskcolumn.ui.theme.AccentBlue
import java.util.Calendar

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun QuickAddBottomSheet(
    onDismiss: () -> Unit,
    onAddTask: (title: String, notes: String?, due: Long?) -> Unit
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    var title by remember { mutableStateOf("") }
    var selectedDueMode by remember { mutableStateOf(0) } // 0: None, 1: Today, 2: Tomorrow
    val focusRequester = remember { FocusRequester() }

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

            // Quick Due Chips
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                FilterChip(
                    selected = selectedDueMode == 1,
                    onClick = { selectedDueMode = if (selectedDueMode == 1) 0 else 1 },
                    label = { Text("今天", fontSize = 12.sp) }
                )
                FilterChip(
                    selected = selectedDueMode == 2,
                    onClick = { selectedDueMode = if (selectedDueMode == 2) 0 else 2 },
                    label = { Text("明天", fontSize = 12.sp) }
                )

                Spacer(modifier = Modifier.weight(1f))

                IconButton(
                    onClick = {
                        val trimmed = title.trim()
                        if (trimmed.isNotEmpty()) {
                            val dueTimestamp = when (selectedDueMode) {
                                1 -> Calendar.getInstance().timeInMillis
                                2 -> Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }.timeInMillis
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
}
