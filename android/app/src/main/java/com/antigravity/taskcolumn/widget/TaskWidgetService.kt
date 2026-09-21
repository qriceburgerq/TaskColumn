package com.antigravity.taskcolumn.widget

import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.antigravity.taskcolumn.R
import com.antigravity.taskcolumn.data.model.TaskItem
import com.antigravity.taskcolumn.data.repository.TaskRepository
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class TaskWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        return TaskRemoteViewsFactory(applicationContext)
    }
}

class TaskRemoteViewsFactory(private val context: Context) : RemoteViewsService.RemoteViewsFactory {
    private var tasks: List<TaskItem> = emptyList()

    override fun onCreate() {
        loadTasks()
    }

    override fun onDataSetChanged() {
        loadTasks()
    }

    private fun loadTasks() {
        // Read uncompleted top-level tasks from repository
        tasks = TaskRepository.shared.allTasks.value.filter { it.isTopLevel && !it.isCompleted }
    }

    override fun onDestroy() {
        tasks = emptyList()
    }

    override fun getCount(): Int = tasks.size

    override fun getViewAt(position: Int): RemoteViews? {
        if (position < 0 || position >= tasks.size) return null
        val task = tasks[position]

        val views = RemoteViews(context.packageName, R.layout.widget_task_item)
        views.setTextViewText(R.id.widget_item_title, task.title)

        // Due date display
        if (task.due != null) {
            views.setViewVisibility(R.id.widget_item_due, View.VISIBLE)
            val dueText = when {
                task.isToday -> "今天到期"
                task.isOverdue -> "已逾期"
                task.isUpcoming -> "即將到來"
                else -> SimpleDateFormat("M/d", Locale.getDefault()).format(Date(task.due!!))
            }
            views.setTextViewText(R.id.widget_item_due, dueText)
        } else {
            views.setViewVisibility(R.id.widget_item_due, View.GONE)
        }

        // 1. Fill-in Intent for checking off task (circle checkbox)
        val toggleIntent = Intent().apply {
            action = TaskWidgetProvider.ACTION_TOGGLE_TASK
            putExtra(TaskWidgetProvider.EXTRA_TASK_ID, task.id)
            putExtra("taskId", task.id)
        }
        views.setOnClickFillInIntent(R.id.widget_item_checkbox_area, toggleIntent)
        views.setOnClickFillInIntent(R.id.widget_item_checkbox, toggleIntent)

        // 2. Fill-in Intent to open task in detail screen (content & row)
        val viewIntent = Intent().apply {
            action = TaskWidgetProvider.ACTION_VIEW_TASK
            putExtra(TaskWidgetProvider.EXTRA_TASK_ID, task.id)
            putExtra("taskId", task.id)
        }
        views.setOnClickFillInIntent(R.id.widget_item_container, viewIntent)
        views.setOnClickFillInIntent(R.id.widget_item_content, viewIntent)

        return views
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = true
}
