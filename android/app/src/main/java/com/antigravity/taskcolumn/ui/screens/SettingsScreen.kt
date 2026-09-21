package com.antigravity.taskcolumn.ui.screens

import android.content.Intent
import android.net.Uri
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
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
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.antigravity.taskcolumn.data.auth.AuthManager
import com.antigravity.taskcolumn.data.repository.TaskRepository
import com.antigravity.taskcolumn.data.settings.AppFontSize
import com.antigravity.taskcolumn.data.settings.AppSettingsManager
import com.antigravity.taskcolumn.ui.theme.*
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    repository: TaskRepository = TaskRepository.shared,
    authManager: AuthManager = AuthManager.shared,
    settingsManager: AppSettingsManager = AppSettingsManager.shared,
    onNavigateBack: () -> Unit
) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val isAuthenticated by authManager.isAuthenticated.collectAsState()
    val userEmail by authManager.userEmail.collectAsState()
    val isAuthorizing by authManager.isAuthorizing.collectAsState()
    val authErrorMessage by authManager.authErrorMessage.collectAsState()
    val isSyncing by repository.isSyncing.collectAsState()
    val syncErrorMessage by repository.syncErrorMessage.collectAsState()
    val lastSyncTime by repository.lastSyncTime.collectAsState()
    val fontScale by settingsManager.fontScale.collectAsState()
    val filterOrder by settingsManager.smartFilterOrder.collectAsState()
    val lists by repository.lists.collectAsState()

    var showSignOutDialog by remember { mutableStateOf(false) }
    var showAddListDialog by remember { mutableStateOf(false) }
    var newListName by remember { mutableStateOf("") }
    var listToDelete by remember { mutableStateOf<Pair<String, String>?>(null) } // id to title

    var showManualCodeDialog by remember { mutableStateOf(false) }
    var manualCodeInput by remember { mutableStateOf("") }
    var isSubmittingManualCode by remember { mutableStateOf(false) }

    var showCustomCredentialsDialog by remember { mutableStateOf(false) }
    var customClientId by remember { mutableStateOf(authManager.getClientId()) }
    var customClientSecret by remember { mutableStateOf(authManager.getClientSecret()) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("設定", fontWeight = FontWeight.Bold, fontSize = 20.sp) },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "返回")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.background,
                    titleContentColor = MaterialTheme.colorScheme.onBackground
                )
            )
        },
        containerColor = MaterialTheme.colorScheme.background
    ) { innerPadding ->
        LazyColumn(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .padding(horizontal = 16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp),
            contentPadding = PaddingValues(vertical = 12.dp)
        ) {
            // Section 1: Google Account Management
            item {
                SettingsSection(
                    title = "Google 帳號與同步",
                    trailingAction = {
                        if (isAuthenticated) {
                            TextButton(
                                onClick = { repository.syncWithGoogle() },
                                enabled = !isSyncing
                            ) {
                                if (isSyncing) {
                                    CircularProgressIndicator(modifier = Modifier.size(14.dp), strokeWidth = 2.dp)
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text("同步中...", fontSize = 12.sp, color = AccentBlue)
                                } else {
                                    Icon(Icons.Default.Sync, contentDescription = null, modifier = Modifier.size(14.dp), tint = AccentBlue)
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text("立即同步", fontSize = 12.sp, color = AccentBlue)
                                }
                            }
                        }
                    }
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                                modifier = Modifier.weight(1f)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(40.dp)
                                        .clip(CircleShape)
                                        .background(if (isAuthenticated) AccentBlue.copy(alpha = 0.2f) else MaterialTheme.colorScheme.surfaceVariant),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        imageVector = if (isAuthenticated) Icons.Default.CloudDone else Icons.Default.CloudOff,
                                        contentDescription = null,
                                        tint = if (isAuthenticated) AccentBlue else MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                                Column {
                                    Text(
                                        text = if (isAuthenticated) "已連線 Google Tasks" else "未連線 (離線單機模式)",
                                        fontSize = 15.sp,
                                        fontWeight = FontWeight.Medium,
                                        color = MaterialTheme.colorScheme.onSurface
                                    )
                                    Text(
                                        text = if (isAuthenticated) {
                                            val email = userEmail ?: "已授權"
                                            val syncStr = lastSyncTime?.let {
                                                " • 上次同步 " + SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date(it))
                                            } ?: ""
                                            email + syncStr
                                        } else "待辦將僅保存在本機快取中",
                                        fontSize = 12.sp,
                                        color = MaterialTheme.colorScheme.onSurfaceVariant
                                    )
                                }
                            }

                            if (isAuthenticated) {
                                OutlinedButton(
                                    onClick = { showSignOutDialog = true },
                                    colors = ButtonDefaults.outlinedButtonColors(contentColor = TrashRed),
                                    border = ButtonDefaults.outlinedButtonBorder.copy(brush = androidx.compose.ui.graphics.SolidColor(TrashRed)),
                                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                                ) {
                                    Text("登出", fontSize = 13.sp)
                                }
                            } else {
                                Button(
                                    onClick = {
                                        authManager.startLocalServer { success, error ->
                                            if (success) {
                                                repository.syncWithGoogle()
                                                Toast.makeText(context, "Google 帳號連線成功！正在同步...", Toast.LENGTH_SHORT).show()
                                            } else if (error != null) {
                                                Toast.makeText(context, error, Toast.LENGTH_LONG).show()
                                            }
                                        }
                                        val authUrl = authManager.buildAuthUrl()
                                        try {
                                            val customTabsIntent = androidx.browser.customtabs.CustomTabsIntent.Builder().build()
                                            customTabsIntent.launchUrl(context, Uri.parse(authUrl))
                                        } catch (_: Exception) {
                                            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(authUrl))
                                            context.startActivity(intent)
                                        }
                                    },
                                    colors = ButtonDefaults.buttonColors(containerColor = AccentBlue),
                                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp)
                                ) {
                                    Text("登入", fontSize = 13.sp, color = Color.White)
                                }
                            }

                        if (isAuthenticated && !syncErrorMessage.isNullOrBlank()) {
                            Text(
                                text = "同步提示：$syncErrorMessage",
                                fontSize = 12.sp,
                                color = TrashRed,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .background(TrashRed.copy(alpha = 0.1f), RoundedCornerShape(6.dp))
                                    .padding(8.dp)
                            )
                        }

                        if (!isAuthenticated) {
                            HorizontalDivider(color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))

                            Text(
                                text = "已內建 Google OAuth 專用憑證（與 Mac 版相同）。點擊「登入」開啟瀏覽器授權；若跳轉受阻，可點擊下方按鈕手動貼入跳轉網址。",
                                fontSize = 12.sp,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )

                            if (isAuthorizing) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(AccentBlue.copy(alpha = 0.1f), RoundedCornerShape(6.dp))
                                        .padding(8.dp)
                                ) {
                                    CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = AccentBlue)
                                    Text("正在監聽本機 8089 端口等待瀏覽器回傳...", fontSize = 12.sp, color = AccentBlue)
                                }
                            }

                            if (!authErrorMessage.isNullOrBlank()) {
                                Text(
                                    text = "錯誤：$authErrorMessage",
                                    fontSize = 12.sp,
                                    color = TrashRed,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .background(TrashRed.copy(alpha = 0.1f), RoundedCornerShape(6.dp))
                                        .padding(8.dp)
                                )
                            }

                            Row(
                                modifier = Modifier.fillMaxWidth(),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                OutlinedButton(
                                    onClick = {
                                        manualCodeInput = ""
                                        showManualCodeDialog = true
                                    },
                                    contentPadding = PaddingValues(horizontal = 10.dp, vertical = 4.dp)
                                ) {
                                    Icon(Icons.Default.Key, contentDescription = null, modifier = Modifier.size(14.dp))
                                    Spacer(modifier = Modifier.width(4.dp))
                                    Text("手動回填授權碼 / 網址", fontSize = 12.sp)
                                }

                                TextButton(
                                    onClick = {
                                        customClientId = authManager.getClientId()
                                        customClientSecret = authManager.getClientSecret()
                                        showCustomCredentialsDialog = true
                                    },
                                    contentPadding = PaddingValues(horizontal = 8.dp, vertical = 4.dp)
                                ) {
                                    Text("自訂憑證", fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                                }
                            }
                        }
                    }
                }
            }

            // Section 2: Font Size Adjustment
            item {
                SettingsSection(title = "全域字體大小") {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        Text(
                            text = "選擇最適合您閱讀的字體比例：",
                            fontSize = 13.sp,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )

                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(8.dp)
                        ) {
                            AppFontSize.values().forEach { size ->
                                val isSelected = (fontScale == size.scale)
                                Box(
                                    modifier = Modifier
                                        .weight(1f)
                                        .clip(RoundedCornerShape(8.dp))
                                        .background(if (isSelected) AccentBlue else MaterialTheme.colorScheme.surfaceVariant)
                                        .clickable { settingsManager.setFontScale(size.scale) }
                                        .padding(vertical = 10.dp),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Text(
                                        text = size.label.substringBefore(" "),
                                        fontSize = 13.sp,
                                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                        color = if (isSelected) Color.White else MaterialTheme.colorScheme.onSurface
                                    )
                                }
                            }
                        }

                        // Preview text
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(8.dp))
                                .background(MaterialTheme.colorScheme.surface)
                                .padding(12.dp)
                        ) {
                            Text(
                                text = "待辦任務標題範例：下午 3:00 與團隊進行線上專案會議 📝",
                                fontSize = 14.sp,
                                color = MaterialTheme.colorScheme.onSurface
                            )
                        }
                    }
                }
            }

            // Section 3: Smart Filter Views Sorting
            item {
                SettingsSection(
                    title = "智慧視角分類排序",
                    trailingAction = {
                        TextButton(onClick = { settingsManager.resetFilterOrder() }) {
                            Text("重設順序", fontSize = 12.sp, color = AccentBlue)
                        }
                    }
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 6.dp)
                    ) {
                        filterOrder.forEachIndexed { index, id ->
                            val (name, icon, color) = getSmartFilterMeta(id)
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 14.dp, vertical = 8.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                                ) {
                                    Icon(imageVector = icon, contentDescription = null, tint = color, modifier = Modifier.size(20.dp))
                                    Text(name, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurface)
                                }

                                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                                    IconButton(
                                        onClick = { settingsManager.moveFilterUp(index) },
                                        enabled = index > 0,
                                        modifier = Modifier.size(32.dp)
                                    ) {
                                        Icon(Icons.Default.KeyboardArrowUp, contentDescription = "上移", tint = if (index > 0) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f))
                                    }
                                    IconButton(
                                        onClick = { settingsManager.moveFilterDown(index) },
                                        enabled = index < filterOrder.size - 1,
                                        modifier = Modifier.size(32.dp)
                                    ) {
                                        Icon(Icons.Default.KeyboardArrowDown, contentDescription = "下移", tint = if (index < filterOrder.size - 1) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurface.copy(alpha = 0.3f))
                                    }
                                }
                            }
                            if (index < filterOrder.size - 1) {
                                HorizontalDivider(modifier = Modifier.padding(horizontal = 14.dp), color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                            }
                        }
                    }
                }
            }

            // Section 4: Task List Management
            item {
                SettingsSection(
                    title = "待辦分類清單管理",
                    trailingAction = {
                        TextButton(onClick = {
                            newListName = ""
                            showAddListDialog = true
                        }) {
                            Icon(Icons.Default.Add, contentDescription = null, modifier = Modifier.size(16.dp), tint = AccentBlue)
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("新增清單", fontSize = 12.sp, color = AccentBlue)
                        }
                    }
                ) {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 6.dp)
                    ) {
                        lists.forEachIndexed { index, list ->
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 14.dp, vertical = 10.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.SpaceBetween
                            ) {
                                Row(
                                    verticalAlignment = Alignment.CenterVertically,
                                    horizontalArrangement = Arrangement.spacedBy(10.dp)
                                ) {
                                    Icon(Icons.Default.FormatListBulleted, contentDescription = null, tint = AccentBlue, modifier = Modifier.size(20.dp))
                                    Text(list.title, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = MaterialTheme.colorScheme.onSurface)
                                }

                                if (list.id != "@default" && list.id != "default" && lists.size > 1) {
                                    IconButton(
                                        onClick = { listToDelete = list.id to list.title },
                                        modifier = Modifier.size(32.dp)
                                    ) {
                                        Icon(Icons.Outlined.Delete, contentDescription = "刪除清單", tint = TrashRed.copy(alpha = 0.8f))
                                    }
                                }
                            }
                            if (index < lists.size - 1) {
                                HorizontalDivider(modifier = Modifier.padding(horizontal = 14.dp), color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f))
                            }
                        }
                    }
                }
            }

            // Section 5: App Info
            item {
                SettingsSection(title = "關於 TaskColumn") {
                    Column(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(14.dp),
                        verticalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("版本", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurface)
                            Text("v1.1.3 (Build 7)", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            Text("Google Tasks 同步", fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurface)
                            Text(if (isAuthenticated) "已啟用 (即時雙向同步)" else "已停用 (單機模式)", fontSize = 14.sp, color = if (isAuthenticated) CheckmarkGreen else MaterialTheme.colorScheme.onSurfaceVariant)
                        }
                    }
                }
            }
        }
    }

    // Sign Out Confirmation Dialog
    if (showSignOutDialog) {
        AlertDialog(
            onDismissRequest = { showSignOutDialog = false },
            title = { Text("登出 Google 帳號？") },
            text = { Text("登出後將切換為離線單機模式。本機現有的待辦資料將完整保留，您可以隨時再次登入重新啟用雙向同步。") },
            confirmButton = {
                Button(
                    onClick = {
                        authManager.signOut()
                        showSignOutDialog = false
                        Toast.makeText(context, "已成功登出 Google 帳號", Toast.LENGTH_SHORT).show()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = TrashRed)
                ) {
                    Text("確定登出", color = Color.White)
                }
            },
            dismissButton = {
                TextButton(onClick = { showSignOutDialog = false }) {
                    Text("取消")
                }
            }
        )
    }

    // Manual Code Dialog
    if (showManualCodeDialog) {
        AlertDialog(
            onDismissRequest = { if (!isSubmittingManualCode) showManualCodeDialog = false },
            title = { Text("手動回填 Google 授權碼 / 網址") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        "若瀏覽器無法自動跳轉回 App，請將瀏覽器網址列的完整跳轉網址（以 http://127.0.0.1:8089/callback?code=... 開頭）或授權碼直接貼入下方：",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedTextField(
                        value = manualCodeInput,
                        onValueChange = { manualCodeInput = it },
                        placeholder = { Text("貼上完整跳轉網址或 code=...") },
                        singleLine = false,
                        maxLines = 3,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        if (manualCodeInput.isNotBlank()) {
                            scope.launch {
                                isSubmittingManualCode = true
                                val res = authManager.handleManualAuthCode(manualCodeInput)
                                isSubmittingManualCode = false
                                if (res.isSuccess) {
                                    showManualCodeDialog = false
                                    Toast.makeText(context, "Google 帳號連線成功！正在同步...", Toast.LENGTH_SHORT).show()
                                    repository.syncWithGoogle()
                                } else {
                                    Toast.makeText(context, "授權失敗: ${res.exceptionOrNull()?.message}", Toast.LENGTH_LONG).show()
                                }
                            }
                        }
                    },
                    enabled = !isSubmittingManualCode && manualCodeInput.isNotBlank(),
                    colors = ButtonDefaults.buttonColors(containerColor = AccentBlue)
                ) {
                    if (isSubmittingManualCode) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp), color = Color.White, strokeWidth = 2.dp)
                    } else {
                        Text("驗證並連線", color = Color.White)
                    }
                }
            },
            dismissButton = {
                TextButton(
                    onClick = { showManualCodeDialog = false },
                    enabled = !isSubmittingManualCode
                ) {
                    Text("取消")
                }
            }
        )
    }

    // Custom Credentials Dialog
    if (showCustomCredentialsDialog) {
        AlertDialog(
            onDismissRequest = { showCustomCredentialsDialog = false },
            title = { Text("自訂 Google Cloud 憑證") },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(
                        "預設已內建桌面專用憑證。若您需要覆蓋為自己的 Google Cloud 專案憑證，可於此設定：",
                        fontSize = 13.sp,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    OutlinedTextField(
                        value = customClientId,
                        onValueChange = { customClientId = it },
                        label = { Text("OAuth Client ID") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                    OutlinedTextField(
                        value = customClientSecret,
                        onValueChange = { customClientSecret = it },
                        label = { Text("OAuth Client Secret") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )
                }
            },
            confirmButton = {
                Button(
                    onClick = {
                        authManager.setCustomCredentials(customClientId, customClientSecret)
                        showCustomCredentialsDialog = false
                        Toast.makeText(context, "已儲存自訂憑證設定", Toast.LENGTH_SHORT).show()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = AccentBlue)
                ) {
                    Text("儲存", color = Color.White)
                }
            },
            dismissButton = {
                Row {
                    TextButton(onClick = {
                        authManager.clearCustomCredentials()
                        customClientId = authManager.getClientId()
                        customClientSecret = authManager.getClientSecret()
                        showCustomCredentialsDialog = false
                        Toast.makeText(context, "已重設為內建預設憑證", Toast.LENGTH_SHORT).show()
                    }) {
                        Text("重設", color = TrashRed)
                    }
                    TextButton(onClick = { showCustomCredentialsDialog = false }) {
                        Text("取消")
                    }
                }
            }
        )
    }

    // Add List Dialog
    if (showAddListDialog) {
        AlertDialog(
            onDismissRequest = { showAddListDialog = false },
            title = { Text("新增待辦清單") },
            text = {
                OutlinedTextField(
                    value = newListName,
                    onValueChange = { newListName = it },
                    placeholder = { Text("例如：工作、學習、購物...") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )
            },
            confirmButton = {
                Button(
                    onClick = {
                        if (newListName.isNotBlank()) {
                            repository.addTaskList(newListName)
                            showAddListDialog = false
                            Toast.makeText(context, "已建立清單：$newListName", Toast.LENGTH_SHORT).show()
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = AccentBlue)
                ) {
                    Text("建立", color = Color.White)
                }
            },
            dismissButton = {
                TextButton(onClick = { showAddListDialog = false }) {
                    Text("取消")
                }
            }
        )
    }

    // Delete List Dialog
    listToDelete?.let { (id, title) ->
        AlertDialog(
            onDismissRequest = { listToDelete = null },
            title = { Text("刪除清單「$title」？") },
            text = { Text("該清單內的所有待辦事項將會移至垃圾桶。此動作無法復原。") },
            confirmButton = {
                Button(
                    onClick = {
                        repository.deleteTaskList(id)
                        listToDelete = null
                        Toast.makeText(context, "已刪除清單：$title", Toast.LENGTH_SHORT).show()
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = TrashRed)
                ) {
                    Text("確認刪除", color = Color.White)
                }
            },
            dismissButton = {
                TextButton(onClick = { listToDelete = null }) {
                    Text("取消")
                }
            }
        )
    }
}

@Composable
private fun SettingsSection(
    title: String,
    trailingAction: (@Composable () -> Unit)? = null,
    content: @Composable () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Text(
                text = title,
                fontSize = 13.sp,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            trailingAction?.invoke()
        }

        Card(
            shape = RoundedCornerShape(12.dp),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f)),
            modifier = Modifier.fillMaxWidth()
        ) {
            content()
        }
    }
}

private fun getSmartFilterMeta(id: String): Triple<String, androidx.compose.ui.graphics.vector.ImageVector, Color> {
    return when (id) {
        "pending" -> Triple("待辦中", Icons.Outlined.Schedule, AccentBlue)
        "today" -> Triple("今天到期", Icons.Default.Star, StarOrange)
        "upcoming" -> Triple("即將到來", Icons.Outlined.CalendarMonth, CalendarTeal)
        "all" -> Triple("全部待辦", Icons.Outlined.Inbox, BoxPurple)
        "completed" -> Triple("已完成事項", Icons.Default.CheckCircle, CheckmarkGreen)
        "trash" -> Triple("垃圾桶", Icons.Outlined.Delete, TrashRed)
        else -> Triple(id, Icons.Default.Folder, AccentBlue)
    }
}
