package com.antigravity.taskcolumn.data.model

import kotlinx.serialization.Serializable
import java.util.Calendar

@Serializable
enum class TaskStatus(val value: String) {
    NEEDS_ACTION("needsAction"),
    COMPLETED("completed")
}

@Serializable
data class TaskItem(
    var id: String,
    var listId: String,
    var title: String,
    var notes: String? = null,
    var due: Long? = null,
    var status: TaskStatus = TaskStatus.NEEDS_ACTION,
    var parent: String? = null,
    var subtasks: MutableList<TaskItem> = mutableListOf(),
    var updated: Long = System.currentTimeMillis(),
    var deletedAt: Long? = null
) {
    val isCompleted: Boolean
        get() = status == TaskStatus.COMPLETED

    val isTopLevel: Boolean
        get() = parent == null || parent == "null" || parent?.isBlank() == true

    val isOverdue: Boolean
        get() {
            if (isCompleted) return false
            val dueTime = due ?: return false
            val calToday = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 0)
                set(Calendar.MINUTE, 0)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            return dueTime < calToday.timeInMillis
        }

    val isToday: Boolean
        get() {
            val dueTime = due ?: return false
            val calDue = Calendar.getInstance().apply { timeInMillis = dueTime }
            val calNow = Calendar.getInstance()
            return calDue.get(Calendar.YEAR) == calNow.get(Calendar.YEAR) &&
                    calDue.get(Calendar.DAY_OF_YEAR) == calNow.get(Calendar.DAY_OF_YEAR)
        }

    val isUpcoming: Boolean
        get() {
            if (isCompleted) return false
            val dueTime = due ?: return false
            val calToday = Calendar.getInstance().apply {
                set(Calendar.HOUR_OF_DAY, 23)
                set(Calendar.MINUTE, 59)
                set(Calendar.SECOND, 59)
                set(Calendar.MILLISECOND, 999)
            }
            return dueTime > calToday.timeInMillis
        }
}

@Serializable
data class TaskList(
    var id: String,
    var title: String,
    var updated: Long = System.currentTimeMillis()
)

sealed class SmartFilterType(val id: String, val title: String) {
    object Pending : SmartFilterType("pending", "待辦中")
    object Today : SmartFilterType("today", "今天到期")
    object Upcoming : SmartFilterType("upcoming", "即將到來")
    object All : SmartFilterType("all", "全部待辦")
    object Completed : SmartFilterType("completed", "已完成事項")
    object Trash : SmartFilterType("trash", "垃圾桶")
    data class CustomList(val listId: String, val listTitle: String) :
        SmartFilterType("list_$listId", listTitle)
}

enum class TaskSortOrder(val displayName: String) {
    MANUAL("自訂排序"),
    DUE_DATE("依到期日"),
    CREATION("依更新時間"),
    TITLE("依標題字母")
}
