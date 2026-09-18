package com.antigravity.taskcolumn.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.widget.RemoteViews
import androidx.annotation.DrawableRes
import androidx.core.content.ContextCompat
import com.antigravity.taskcolumn.MainActivity
import com.antigravity.taskcolumn.R
import com.antigravity.taskcolumn.data.repository.TaskRepository

class TaskWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
        for (appWidgetId in appWidgetIds) {
            updateAppWidget(context, appWidgetManager, appWidgetId)
        }
        super.onUpdate(context, appWidgetManager, appWidgetIds)
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        when (intent.action) {
            ACTION_TOGGLE_TASK -> {
                val taskId = intent.getStringExtra(EXTRA_TASK_ID)
                if (!taskId.isNullOrBlank()) {
                    TaskRepository.shared.toggleTaskCompletion(taskId)
                    updateAllWidgets(context)
                }
            }
            ACTION_REFRESH_WIDGET -> {
                TaskRepository.shared.syncWithGoogle()
                updateAllWidgets(context)
            }
        }
    }

    companion object {
        const val ACTION_TOGGLE_TASK = "com.antigravity.taskcolumn.widget.ACTION_TOGGLE_TASK"
        const val ACTION_REFRESH_WIDGET = "com.antigravity.taskcolumn.widget.ACTION_REFRESH_WIDGET"
        const val ACTION_VIEW_TASK = "com.antigravity.taskcolumn.widget.ACTION_VIEW_TASK"
        const val EXTRA_TASK_ID = "extra_task_id"

        private fun vectorToBitmap(context: Context, @DrawableRes resId: Int, sizeDp: Int = 24): Bitmap {
            val drawable = ContextCompat.getDrawable(context, resId)
                ?: return Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
            val density = context.resources.displayMetrics.density
            val px = (sizeDp * density).toInt().coerceAtLeast(1)
            val bitmap = Bitmap.createBitmap(px, px, Bitmap.Config.ARGB_8888)
            val canvas = Canvas(bitmap)
            drawable.setBounds(0, 0, px, px)
            drawable.draw(canvas)
            return bitmap
        }

        fun updateAppWidget(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int) {
            val views = RemoteViews(context.packageName, R.layout.widget_task_list)

            // Safely set rasterized bitmaps for vector icons to avoid RemoteViews cross-process vector crash
            views.setImageViewBitmap(
                R.id.widget_btn_refresh,
                vectorToBitmap(context, R.drawable.ic_widget_sync, 24)
            )
            views.setImageViewBitmap(
                R.id.widget_btn_add,
                vectorToBitmap(context, R.drawable.ic_widget_add, 24)
            )

            // Setup ListView Adapter via RemoteViewsService
            val serviceIntent = Intent(context, TaskWidgetService::class.java).apply {
                putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
            }
            views.setRemoteAdapter(R.id.widget_task_listview, serviceIntent)
            views.setEmptyView(R.id.widget_task_listview, R.id.widget_empty_view)

            // Header Click: Open App
            val openAppIntent = Intent(context, MainActivity::class.java)
            val openAppPendingIntent = PendingIntent.getActivity(
                context, 0, openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_title, openAppPendingIntent)

            // Refresh Button Click
            val refreshIntent = Intent(context, TaskWidgetProvider::class.java).apply {
                action = ACTION_REFRESH_WIDGET
            }
            val refreshPendingIntent = PendingIntent.getBroadcast(
                context, 1, refreshIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_btn_refresh, refreshPendingIntent)

            // Add Task Button Click: Open App
            val addIntent = Intent(context, MainActivity::class.java).apply {
                putExtra("action", "quick_add")
            }
            val addPendingIntent = PendingIntent.getActivity(
                context, 2, addIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            views.setOnClickPendingIntent(R.id.widget_btn_add, addPendingIntent)

            // ListItem Click Template pointing to TaskWidgetRouterActivity
            val clickIntentTemplate = Intent(context, TaskWidgetRouterActivity::class.java)
            val clickPendingIntentTemplate = PendingIntent.getActivity(
                context, 3, clickIntentTemplate,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            )
            views.setPendingIntentTemplate(R.id.widget_task_listview, clickPendingIntentTemplate)

            appWidgetManager.updateAppWidget(appWidgetId, views)
            appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_task_listview)
        }

        fun updateAllWidgets(context: Context) {
            val appWidgetManager = AppWidgetManager.getInstance(context)
            val componentName = ComponentName(context, TaskWidgetProvider::class.java)
            val appWidgetIds = appWidgetManager.getAppWidgetIds(componentName)
            if (appWidgetIds.isNotEmpty()) {
                for (id in appWidgetIds) {
                    updateAppWidget(context, appWidgetManager, id)
                }
            }
        }
    }
}
