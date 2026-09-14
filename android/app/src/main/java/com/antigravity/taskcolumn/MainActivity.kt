package com.antigravity.taskcolumn

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
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
import com.antigravity.taskcolumn.data.auth.AuthManager
import com.antigravity.taskcolumn.data.repository.TaskRepository
import com.antigravity.taskcolumn.ui.screens.HomeScreen
import com.antigravity.taskcolumn.ui.screens.TaskDetailScreen
import com.antigravity.taskcolumn.ui.theme.TaskColumnTheme
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private val authManager = AuthManager.shared
    private val repository = TaskRepository.shared

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleAuthIntent(intent)

        setContent {
            TaskColumnTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val navController = rememberNavController()

                    NavHost(navController = navController, startDestination = "home") {
                        composable("home") {
                            HomeScreen(
                                repository = repository,
                                authManager = authManager,
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
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleAuthIntent(intent)
    }

    private fun handleAuthIntent(intent: Intent?) {
        val uri = intent?.data ?: return
        if (uri.scheme == "com.antigravity.taskcolumn") {
            val code = uri.getQueryParameter("code")
            if (code != null) {
                lifecycleScope.launch {
                    val res = authManager.exchangeCodeForToken(code)
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
