package com.antigravity.taskcolumn.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.taskcolumn.data.model.TaskItem
import com.antigravity.taskcolumn.data.repository.TaskRepository
import com.antigravity.taskcolumn.ui.theme.AccentBlue
import com.antigravity.taskcolumn.ui.theme.TrashRed
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TaskDetailScreen(
    taskId: String,
    repository: TaskRepository = TaskRepository.shared,
    onNavigateBack: () -> Unit
) {
    val allTasks by repository.allTasks.collectAsState()
    val trashTasks by repository.trashTasks.collectAsState()

    val task = remember(allTasks, trashTasks, taskId) {
        allTasks.find { it.id == taskId } ?: trashTasks.find { it.id == taskId }
    }

    if (task == null) {
        LaunchedEffect(Unit) { onNavigateBack() }
        return
    }

    var titleText by remember(task.title) { mutableStateOf(task.title) }
    var notesText by remember(task.notes) { mutableStateOf(task.notes ?: "") }
    var showDatePicker by remember { mutableStateOf(false) }

    val datePickerState = rememberDatePickerState(
        initialSelectedDateMillis = task.due ?: System.currentTimeMillis()
    )

    Scaffold(
        topBar = {
            TopAppBar(
                title = {},
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(imageVector = Icons.Default.ArrowBack, contentDescription = "返回")
                    }
                },
                actions = {
                    IconButton(onClick = {
                        repository.deleteTask(task.id)
                        onNavigateBack()
                    }) {
                        Icon(imageVector = Icons.Outlined.Delete, contentDescription = "移入垃圾桶", tint = TrashRed)
                    }
                }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp)
        ) {
            // Title Input (Borderless, 22sp bold)
            TextField(
                value = titleText,
                onValueChange = {
                    titleText = it
                    repository.updateTask(task.copy(title = it))
                },
                placeholder = {
                    Text("任務標題...", fontSize = 22.sp, fontWeight = FontWeight.Bold)
                },
                textStyle = MaterialTheme.typography.headlineSmall.copy(fontWeight = FontWeight.Bold),
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent
                ),
                modifier = Modifier.fillMaxWidth()
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Due Date Picker Chip / Row
            Surface(
                shape = RoundedCornerShape(8.dp),
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { showDatePicker = true }
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 14.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Icon(imageVector = Icons.Default.CalendarMonth, contentDescription = null, tint = AccentBlue)
                    Column(modifier = Modifier.weight(1f)) {
                        Text(text = "到期日", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        val dueStr = task.due?.let {
                            SimpleDateFormat("yyyy 年 M 月 d 日", Locale.getDefault()).format(Date(it))
                        } ?: "尚未設定到期日"
                        Text(text = dueStr, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                    }
                    if (task.due != null) {
                        IconButton(
                            onClick = {
                                repository.updateTask(task.copy(due = null))
                            },
                            modifier = Modifier.size(24.dp)
                        ) {
                            Icon(imageVector = Icons.Default.Close, contentDescription = "清除到期日", tint = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            HorizontalDivider()

            Spacer(modifier = Modifier.height(14.dp))

            // Notion-Style Multi-line Notes Editor
            Text(
                text = "備忘筆記",
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )

            Spacer(modifier = Modifier.height(8.dp))

            TextField(
                value = notesText,
                onValueChange = {
                    notesText = it
                    repository.updateTask(task.copy(notes = it))
                },
                placeholder = {
                    Text("輸入詳細備忘、待辦筆記、重要連結...", fontSize = 15.sp, color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f))
                },
                colors = TextFieldDefaults.colors(
                    focusedContainerColor = Color.Transparent,
                    unfocusedContainerColor = Color.Transparent,
                    focusedIndicatorColor = Color.Transparent,
                    unfocusedIndicatorColor = Color.Transparent
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .defaultMinSize(minHeight = 260.dp)
            )
        }

        if (showDatePicker) {
            DatePickerDialog(
                onDismissRequest = { showDatePicker = false },
                confirmButton = {
                    TextButton(onClick = {
                        datePickerState.selectedDateMillis?.let { selected ->
                            repository.updateTask(task.copy(due = selected))
                        }
                        showDatePicker = false
                    }) {
                        Text("確定")
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
}
