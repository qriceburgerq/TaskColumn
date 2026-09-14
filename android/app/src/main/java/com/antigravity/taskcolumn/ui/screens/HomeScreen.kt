package com.antigravity.taskcolumn.ui.screens

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import android.widget.Toast
import com.antigravity.taskcolumn.data.auth.AuthManager
import com.antigravity.taskcolumn.data.model.SmartFilterType
import com.antigravity.taskcolumn.data.model.TaskItem
import com.antigravity.taskcolumn.data.model.TaskStatus
import com.antigravity.taskcolumn.data.repository.TaskRepository
import com.antigravity.taskcolumn.data.settings.AppSettingsManager
import com.antigravity.taskcolumn.ui.theme.*
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(
    repository: TaskRepository = TaskRepository.shared,
    authManager: AuthManager = AuthManager.shared,
    settingsManager: AppSettingsManager = AppSettingsManager.shared,
    initialAction: String? = null,
    onClearInitialAction: () -> Unit = {},
    onNavigateToSettings: () -> Unit = {},
    onNavigateToDetail: (String) -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val drawerState = rememberDrawerState(initialValue = DrawerValue.Closed)

    val allTasks by repository.allTasks.collectAsState()
    val trashTasks by repository.trashTasks.collectAsState()
    val lists by repository.lists.collectAsState()
    val selectedFilter by repository.selectedFilter.collectAsState()
    val isSyncing by repository.isSyncing.collectAsState()
    val searchQuery by repository.searchQuery.collectAsState()
    val isAuthenticated by authManager.isAuthenticated.collectAsState()
    val userEmail by authManager.userEmail.collectAsState()
    val filterOrder by settingsManager.smartFilterOrder.collectAsState()

    var showQuickAddSheet by remember { mutableStateOf(false) }

    LaunchedEffect(initialAction) {
        if (initialAction == "quick_add") {
            showQuickAddSheet = true
            onClearInitialAction()
        }
    }

    // Filter tasks based on selectedFilter & search
    val displayedTasks = remember(allTasks, trashTasks, selectedFilter, searchQuery) {
        val base = when (selectedFilter) {
            is SmartFilterType.Pending -> allTasks.filter { it.parent == null && !it.isCompleted }
            is SmartFilterType.Today -> allTasks.filter { it.parent == null && (it.isToday || it.isOverdue) }
            is SmartFilterType.Upcoming -> allTasks.filter { it.parent == null && it.isUpcoming }
            is SmartFilterType.All -> allTasks.filter { it.parent == null }
            is SmartFilterType.Completed -> allTasks.filter { it.parent == null && it.isCompleted }
            is SmartFilterType.Trash -> trashTasks
            is SmartFilterType.CustomList -> {
                val lid = (selectedFilter as SmartFilterType.CustomList).listId
                allTasks.filter { it.parent == null && it.listId == lid }
            }
        }
        if (searchQuery.isBlank()) base else {
            val q = searchQuery.lowercase()
            base.filter {
                it.title.lowercase().contains(q) || (it.notes?.lowercase()?.contains(q) == true)
            }
        }
    }

    ModalNavigationDrawer(
        drawerState = drawerState,
        drawerContent = {
            ModalDrawerSheet(
                modifier = Modifier.width(310.dp)
            ) {
                // Header
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(20.dp)
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        Box(
                            modifier = Modifier
                                .size(36.dp)
                                .clip(RoundedCornerShape(8.dp))
                                .background(AccentBlue),
                            contentAlignment = Alignment.Center
                        ) {
                            Icon(
                                imageVector = Icons.Default.Checklist,
                                contentDescription = null,
                                tint = Color.White
                            )
                        }
                        Text(
                            text = "TaskColumn",
                            fontSize = 20.sp,
                            fontWeight = FontWeight.Bold
                        )
                    }

                    Spacer(modifier = Modifier.height(14.dp))

                    // Google Account Status
                    Surface(
                        shape = RoundedCornerShape(10.dp),
                        color = if (isAuthenticated) CheckmarkGreen.copy(alpha = 0.12f) else MaterialTheme.colorScheme.surfaceVariant,
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable {
                                if (!isAuthenticated) {
                                    val authUrl = authManager.buildAuthUrl()
                                    try {
                                        val customTabsIntent = androidx.browser.customtabs.CustomTabsIntent.Builder().build()
                                        customTabsIntent.launchUrl(context, Uri.parse(authUrl))
                                    } catch (_: Exception) {
                                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(authUrl))
                                        context.startActivity(intent)
                                    }
                                }
                            }
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            Icon(
                                imageVector = if (isAuthenticated) Icons.Default.CloudDone else Icons.Default.AccountCircle,
                                contentDescription = null,
                                tint = if (isAuthenticated) CheckmarkGreen else MaterialTheme.colorScheme.primary,
                                modifier = Modifier.size(20.dp)
                            )
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = if (isAuthenticated) "Google 雲端已連線" else "登入 Google 帳號",
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.SemiBold
                                )
                                if (userEmail != null) {
                                    Text(
                                        text = userEmail!!,
                                        fontSize = 11.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                                        maxLines = 1,
                                        overflow = TextOverflow.Ellipsis
                                    )
                                }
                            }
                        }
                    }
                }

                HorizontalDivider()

                // Smart Filters Section
                Text(
                    text = "智慧視角",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, top = 12.dp, bottom = 4.dp)
                )

                filterOrder.forEach { filterId ->
                    when (filterId) {
                        "pending" -> DrawerItem(
                            title = "待辦中",
                            icon = Icons.Outlined.Schedule,
                            iconColor = AccentBlue,
                            count = allTasks.count { !it.isCompleted },
                            isSelected = selectedFilter is SmartFilterType.Pending,
                            onClick = {
                                repository.setFilter(SmartFilterType.Pending)
                                scope.launch { drawerState.close() }
                            }
                        )
                        "today" -> DrawerItem(
                            title = "今天到期",
                            icon = Icons.Default.Star,
                            iconColor = StarOrange,
                            count = allTasks.count { !it.isCompleted && (it.isToday || it.isOverdue) },
                            isSelected = selectedFilter is SmartFilterType.Today,
                            onClick = {
                                repository.setFilter(SmartFilterType.Today)
                                scope.launch { drawerState.close() }
                            }
                        )
                        "upcoming" -> DrawerItem(
                            title = "即將到來",
                            icon = Icons.Outlined.CalendarMonth,
                            iconColor = CalendarTeal,
                            count = allTasks.count { !it.isCompleted && it.isUpcoming },
                            isSelected = selectedFilter is SmartFilterType.Upcoming,
                            onClick = {
                                repository.setFilter(SmartFilterType.Upcoming)
                                scope.launch { drawerState.close() }
                            }
                        )
                        "all" -> DrawerItem(
                            title = "全部待辦",
                            icon = Icons.Outlined.Inbox,
                            iconColor = BoxPurple,
                            count = allTasks.size,
                            isSelected = selectedFilter is SmartFilterType.All,
                            onClick = {
                                repository.setFilter(SmartFilterType.All)
                                scope.launch { drawerState.close() }
                            }
                        )
                        "completed" -> DrawerItem(
                            title = "已完成事項",
                            icon = Icons.Default.CheckCircle,
                            iconColor = CheckmarkGreen,
                            count = allTasks.count { it.isCompleted },
                            isSelected = selectedFilter is SmartFilterType.Completed,
                            onClick = {
                                repository.setFilter(SmartFilterType.Completed)
                                scope.launch { drawerState.close() }
                            }
                        )
                        "trash" -> DrawerItem(
                            title = "垃圾桶",
                            icon = Icons.Outlined.Delete,
                            iconColor = TrashRed,
                            count = trashTasks.size,
                            isSelected = selectedFilter is SmartFilterType.Trash,
                            onClick = {
                                repository.setFilter(SmartFilterType.Trash)
                                scope.launch { drawerState.close() }
                            }
                        )
                    }
                }

                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

                // Custom Lists
                Text(
                    text = "待辦分類清單",
                    fontSize = 12.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 16.dp, top = 4.dp, bottom = 4.dp)
                )

                lists.forEach { list ->
                    DrawerItem(
                        title = list.title,
                        icon = Icons.Default.FormatListBulleted,
                        iconColor = MaterialTheme.colorScheme.primary,
                        count = allTasks.count { it.listId == list.id && !it.isCompleted },
                        isSelected = (selectedFilter as? SmartFilterType.CustomList)?.listId == list.id,
                        onClick = {
                            repository.setFilter(SmartFilterType.CustomList(list.id, list.title))
                            scope.launch { drawerState.close() }
                        }
                    )
                }

                Spacer(modifier = Modifier.weight(1f))
                HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable {
                            scope.launch { drawerState.close() }
                            onNavigateToSettings()
                        }
                        .padding(horizontal = 16.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                ) {
                    Icon(
                        imageVector = Icons.Default.Settings,
                        contentDescription = "設定",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.size(20.dp)
                    )
                    Text(
                        text = "設定 (偏好與帳號)",
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium,
                        color = MaterialTheme.colorScheme.onSurface
                    )
                }
            }
        }
    ) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = {
                        Text(
                            text = selectedFilter.title,
                            fontSize = 18.sp,
                            fontWeight = FontWeight.Bold
                        )
                    },
                    navigationIcon = {
                        IconButton(onClick = { scope.launch { drawerState.open() } }) {
                            Icon(imageVector = Icons.Default.Menu, contentDescription = "選單")
                        }
                    },
                    actions = {
                        // Sync Button
                        IconButton(
                            onClick = { repository.syncWithGoogle() },
                            enabled = isAuthenticated && !isSyncing
                        ) {
                            if (isSyncing) {
                                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                            } else {
                                Icon(imageVector = Icons.Default.Sync, contentDescription = "雙向同步")
                            }
                        }

                        // Batch action button for Completed
                        if (selectedFilter is SmartFilterType.Completed && displayedTasks.isNotEmpty()) {
                            IconButton(onClick = { repository.trashAllCompletedTasks() }) {
                                Icon(imageVector = Icons.Outlined.DeleteSweep, contentDescription = "全部移入垃圾桶", tint = TrashRed)
                            }
                        }

                        // Batch action button for Trash
                        if (selectedFilter is SmartFilterType.Trash && trashTasks.isNotEmpty()) {
                            IconButton(onClick = { repository.emptyTrash() }) {
                                Icon(imageVector = Icons.Default.DeleteForever, contentDescription = "清空垃圾桶", tint = TrashRed)
                            }
                        }

                        // Settings Button
                        IconButton(onClick = onNavigateToSettings) {
                            Icon(imageVector = Icons.Default.Settings, contentDescription = "設定")
                        }
                    }
                )
            },
            floatingActionButton = {
                if (selectedFilter !is SmartFilterType.Trash) {
                    FloatingActionButton(
                        onClick = { showQuickAddSheet = true },
                        containerColor = AccentBlue,
                        contentColor = Color.White
                    ) {
                        Icon(imageVector = Icons.Default.Add, contentDescription = "新增待辦")
                    }
                }
            }
        ) { paddingValues ->
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .padding(paddingValues)
            ) {
                if (displayedTasks.isEmpty()) {
                    Column(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Icon(
                            imageVector = if (selectedFilter is SmartFilterType.Trash) Icons.Outlined.Delete else Icons.Outlined.CheckCircleOutline,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                            modifier = Modifier.size(64.dp)
                        )
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = if (selectedFilter is SmartFilterType.Trash) "垃圾桶目前是空的" else "無待辦事項",
                            fontSize = 15.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        contentPadding = PaddingValues(horizontal = 14.dp, vertical = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        items(displayedTasks, key = { it.id }) { task ->
                            TaskCard(
                                task = task,
                                isTrash = selectedFilter is SmartFilterType.Trash,
                                onToggleCompletion = { repository.toggleTaskCompletion(task.id) },
                                onClick = { onNavigateToDetail(task.id) },
                                onRestore = { repository.restoreTask(task.id) },
                                onDelete = { repository.deleteTask(task.id) }
                            )
                        }
                    }
                }
            }

            if (showQuickAddSheet) {
                QuickAddBottomSheet(
                    onDismiss = { showQuickAddSheet = false },
                    onAddTask = { title, notes, due ->
                        repository.addTask(title = title, notes = notes, due = due)
                        showQuickAddSheet = false
                    }
                )
            }
        }
    }
}

@Composable
fun DrawerItem(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    iconColor: Color,
    count: Int,
    isSelected: Boolean,
    onClick: () -> Unit
) {
    Surface(
        shape = RoundedCornerShape(8.dp),
        color = if (isSelected) AccentBlue.copy(alpha = 0.15f) else Color.Transparent,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 10.dp, vertical = 2.dp)
            .clickable(onClick = onClick)
    ) {
        Row(
            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp)
        ) {
            Icon(imageVector = icon, contentDescription = null, tint = iconColor, modifier = Modifier.size(20.dp))
            Text(
                text = title,
                fontSize = 14.sp,
                fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Normal,
                color = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurface,
                modifier = Modifier.weight(1f)
            )
            if (count > 0) {
                Text(
                    text = "$count",
                    fontSize = 11.sp,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier
                        .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f), RoundedCornerShape(6.dp))
                        .padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
        }
    }
}

@Composable
fun TaskCard(
    task: TaskItem,
    isTrash: Boolean,
    onToggleCompletion: () -> Unit,
    onClick: () -> Unit,
    onRestore: () -> Unit,
    onDelete: () -> Unit
) {
    Surface(
        shape = RoundedCornerShape(10.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .clickable(onClick = onClick)
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.Top,
            horizontalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            if (!isTrash) {
                IconButton(
                    onClick = onToggleCompletion,
                    modifier = Modifier.size(24.dp)
                ) {
                    Icon(
                        imageVector = if (task.isCompleted) Icons.Default.CheckCircle else Icons.Outlined.Circle,
                        contentDescription = "完成狀態",
                        tint = if (task.isCompleted) MaterialTheme.colorScheme.onSurfaceVariant else AccentBlue
                    )
                }
            }

            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = task.title,
                    fontSize = 15.sp,
                    fontWeight = FontWeight.Medium,
                    textDecoration = if (task.isCompleted) TextDecoration.LineThrough else TextDecoration.None,
                    color = if (task.isCompleted) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface
                )

                // Chips row (Due date, subtasks, notes)
                if (task.due != null || task.subtasks.isNotEmpty() || !task.notes.isNullOrBlank()) {
                    Spacer(modifier = Modifier.height(6.dp))
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        task.due?.let { dueTime ->
                            val f = SimpleDateFormat("M/d", Locale.getDefault())
                            val dueColor = when {
                                task.isCompleted -> MaterialTheme.colorScheme.onSurfaceVariant
                                task.isOverdue -> TrashRed
                                task.isToday -> StarOrange
                                else -> CalendarTeal
                            }
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(3.dp),
                                modifier = Modifier
                                    .background(dueColor.copy(alpha = 0.12f), RoundedCornerShape(4.dp))
                                    .padding(horizontal = 6.dp, vertical = 2.dp)
                            ) {
                                Icon(imageVector = Icons.Default.CalendarToday, contentDescription = null, tint = dueColor, modifier = Modifier.size(11.dp))
                                Text(text = f.format(Date(dueTime)), fontSize = 11.sp, color = dueColor, fontWeight = FontWeight.SemiBold)
                            }
                        }

                        if (!task.notes.isNullOrBlank()) {
                            Icon(imageVector = Icons.Default.Notes, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(14.dp))
                        }
                    }
                }
            }

            if (isTrash) {
                TextButton(onClick = onRestore) {
                    Text("還原", fontSize = 12.sp)
                }
            }
        }
    }
}
