package com.antigravity.taskcolumn

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import com.antigravity.taskcolumn.data.auth.AuthManager
import com.antigravity.taskcolumn.data.repository.TaskRepository
import com.antigravity.taskcolumn.data.settings.AppSettingsManager
import com.antigravity.taskcolumn.ui.screens.HomeScreen
import com.antigravity.taskcolumn.ui.screens.SettingsScreen
import com.antigravity.taskcolumn.ui.screens.TaskDetailScreen
import com.antigravity.taskcolumn.ui.theme.TaskColumnTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val authManager = AuthManager.shared
    private val repository = TaskRepository.shared
    private val settingsManager = AppSettingsManager.shared

    private val pendingWidgetTaskId = MutableStateFlow<String?>(null)
    private val pendingWidgetAction = MutableStateFlow<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT)
        )
        super.onCreate(savedInstanceState)
        handleAuthIntent(intent)

        pendingWidgetTaskId.value = intent?.getStringExtra("taskId")
        pendingWidgetAction.value = intent?.getStringExtra("action")

        // Auto sync if user already authenticated
        if (authManager.hasValidToken()) {
            repository.syncWithGoogle()
        }

        setContent {
            val fontScale by settingsManager.fontScale.collectAsState()
            val currentDensity = LocalDensity.current
            val customDensity = Density(
                density = currentDensity.density,
                fontScale = currentDensity.fontScale * fontScale
            )

            CompositionLocalProvider(LocalDensity provides customDensity) {
                TaskColumnTheme {
                    Surface(
                        modifier = Modifier.fillMaxSize(),
                        color = MaterialTheme.colorScheme.background
                    ) {
                        val navController = rememberNavController()
                        val targetTaskId by pendingWidgetTaskId.collectAsState()
                        val targetAction by pendingWidgetAction.collectAsState()

                        LaunchedEffect(targetTaskId) {
                            targetTaskId?.let {
                                navController.navigate("detail/$it")
                                pendingWidgetTaskId.value = null
                            }
                        }

                        NavHost(navController = navController, startDestination = "home") {
                            composable("home") {
                                HomeScreen(
                                    repository = repository,
                                    authManager = authManager,
                                    settingsManager = settingsManager,
                                    initialAction = targetAction,
                                    onClearInitialAction = { pendingWidgetAction.value = null },
                                    onNavigateToSettings = { navController.navigate("settings") },
                                    onNavigateToDetail = { taskId ->
                                        navController.navigate("detail/$taskId")
                                    }
                                )
                            }

                            composable(
                                route = "detail/{taskId}",
                                arguments = listOf(navArgument("taskId") { type = NavType.StringType })
                            ) { backStackEntry ->
                                val taskId = backStackEntry.arguments?.getString("taskId") ?: ""
                                TaskDetailScreen(
                                    taskId = taskId,
                                    repository = repository,
                                    onNavigateBack = { navController.popBackStack() }
                                )
                            }

                            composable("settings") {
                                SettingsScreen(
                                    repository = repository,
                                    authManager = authManager,
                                    settingsManager = settingsManager,
                                    onNavigateBack = { navController.popBackStack() }
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Auto pull latest tasks on resume if authenticated
        if (authManager.hasValidToken()) {
            repository.syncWithGoogle()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        authManager.stopLocalServer()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleAuthIntent(intent)
        intent.getStringExtra("taskId")?.let { pendingWidgetTaskId.value = it }
        intent.getStringExtra("action")?.let { pendingWidgetAction.value = it }
    }

    private fun handleAuthIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme == "com.antigravity.taskcolumn") {
            val code = uri.getQueryParameter("code")
            if (code != null) {
                lifecycleScope.launch {
                    var res = authManager.exchangeCodeForToken(code, authManager.redirectUri)
                    if (res.isFailure && res.exceptionOrNull()?.message?.contains("redirect_uri") == true) {
                        res = authManager.exchangeCodeForToken(code, authManager.fallbackSchemeRedirectUri)
                    }
                    if (res.isSuccess) {
                        Toast.makeText(this@MainActivity, "Google 帳號連線成功！正在同步...", Toast.LENGTH_SHORT).show()
                        repository.syncWithGoogle()
                    } else {
                        Toast.makeText(this@MainActivity, "授權失敗: ${res.exceptionOrNull()?.message}", Toast.LENGTH_LONG).show()
                    }
                }
            } else {
                val error = uri.getQueryParameter("error")
                if (error != null) {
                    Toast.makeText(this@MainActivity, "授權取消或失敗: $error", Toast.LENGTH_LONG).show()
                }
            }
        }
    }
}
