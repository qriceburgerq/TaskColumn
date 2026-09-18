package com.antigravity.taskcolumn.widget

import android.app.Activity
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.widget.Toast
import com.antigravity.taskcolumn.MainActivity
import com.antigravity.taskcolumn.data.repository.TaskRepository

/**
 * Lightweight, completely transparent router Activity for Desktop Widget clicks.
 *
 * It fulfills two critical requirements:
 * 1. Safely launches MainActivity with task details without violating Android 12+ Background Activity Launch (BAL) restrictions.
 * 2. Directly toggles task completion status in milliseconds with zero screen flicker and immediately finishes.
 */
class TaskWidgetRouterActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        disableAnimations()

        val action = intent.action
        val taskId = intent.getStringExtra(TaskWidgetProvider.EXTRA_TASK_ID)
            ?: intent.getStringExtra("taskId")

        if (action == TaskWidgetProvider.ACTION_TOGGLE_TASK) {
            handleToggleTask(taskId)
        } else {
            handleViewTask(taskId)
        }
    }

    private fun handleToggleTask(taskId: String?) {
        if (!taskId.isNullOrBlank()) {
            val repository = TaskRepository.shared
            val task = repository.allTasks.value.find { it.id == taskId }
            val title = task?.title

            repository.toggleTaskCompletion(taskId)

            val message = if (!title.isNullOrBlank()) {
                val shortTitle = if (title.length > 15) title.take(15) + "…" else title
                "已完成：$shortTitle"
            } else {
                "已完成待辦"
            }
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show()
        }
        finish()
        disableAnimations()
    }

    private fun handleViewTask(taskId: String?) {
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            if (!taskId.isNullOrBlank()) {
                putExtra("taskId", taskId)
                putExtra(TaskWidgetProvider.EXTRA_TASK_ID, taskId)
            }
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        startActivity(mainIntent)
        finish()
        disableAnimations()
    }

    private fun disableAnimations() {
        if (Build.VERSION.SDK_INT >= 34) {
            overrideActivityTransition(OVERRIDE_TRANSITION_OPEN, 0, 0)
            overrideActivityTransition(OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }
}
