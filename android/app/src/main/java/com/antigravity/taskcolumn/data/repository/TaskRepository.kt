package com.antigravity.taskcolumn.data.repository

import com.antigravity.taskcolumn.data.api.GoogleTasksApi
import com.antigravity.taskcolumn.data.auth.AuthManager
import com.antigravity.taskcolumn.data.model.SmartFilterType
import com.antigravity.taskcolumn.data.model.TaskItem
import com.antigravity.taskcolumn.data.model.TaskList
import com.antigravity.taskcolumn.data.model.TaskStatus
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.util.UUID

class TaskRepository(
    private val api: GoogleTasksApi = GoogleTasksApi(),
    private val authManager: AuthManager = AuthManager.shared,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Main)
) {
    private val _allTasks = MutableStateFlow<List<TaskItem>>(emptyList())
    val allTasks: StateFlow<List<TaskItem>> = _allTasks.asStateFlow()

    private val _lists = MutableStateFlow<List<TaskList>>(listOf(TaskList("default", "主要待辦")))
    val lists: StateFlow<List<TaskList>> = _lists.asStateFlow()

    private val _trashTasks = MutableStateFlow<List<TaskItem>>(emptyList())
    val trashTasks: StateFlow<List<TaskItem>> = _trashTasks.asStateFlow()

    private val _selectedFilter = MutableStateFlow<SmartFilterType>(SmartFilterType.Pending)
    val selectedFilter: StateFlow<SmartFilterType> = _selectedFilter.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    init {
        // Provide sample starter tasks if empty
        if (_allTasks.value.isEmpty()) {
            _allTasks.value = listOf(
                TaskItem(
                    id = UUID.randomUUID().toString(),
                    listId = "default",
                    title = "歡迎使用 TaskColumn 手機版！",
                    notes = "登入 Google 帳號後，所有待辦與 Mac 桌面端即時無縫同步。",
                    due = System.currentTimeMillis()
                ),
                TaskItem(
                    id = UUID.randomUUID().toString(),
                    listId = "default",
                    title = "點選右下方「+」快速新增待辦事項",
                    notes = "支援設定自訂到期日與詳細備忘。"
                )
            )
        }
    }

    fun setFilter(filter: SmartFilterType) {
        _selectedFilter.value = filter
    }

    fun setSearchQuery(q: String) {
        _searchQuery.value = q
    }

    fun syncWithGoogle() {
        if (!authManager.hasValidToken()) return
        if (_isSyncing.value) return

        scope.launch {
            _isSyncing.value = true
            val listsResult = api.fetchTaskLists()
            listsResult.onSuccess { remoteLists ->
                _lists.value = remoteLists
                val collected = mutableListOf<TaskItem>()
                for (l in remoteLists) {
                    val tasksResult = api.fetchTasks(l.id)
                    tasksResult.onSuccess { tasks ->
                        collected.addAll(tasks)
                    }
                }
                _allTasks.value = collected
                notifyWidgetUpdate()
            }
            _isSyncing.value = false
        }
    }

    private fun notifyWidgetUpdate() {
        try {
            com.antigravity.taskcolumn.widget.TaskWidgetProvider.updateAllWidgets(
                com.antigravity.taskcolumn.TaskColumnApplication.instance
            )
        } catch (_: Exception) {}
    }

    fun addTask(title: String, notes: String? = null, due: Long? = null, listId: String? = null): TaskItem {
        val targetListId = listId ?: _lists.value.firstOrNull()?.id ?: "default"
        val newTask = TaskItem(
            id = UUID.randomUUID().toString(),
            listId = targetListId,
            title = title.trim(),
            notes = notes?.trim(),
            due = due
        )

        val updatedList = _allTasks.value.toMutableList()
        updatedList.add(0, newTask)
        _allTasks.value = updatedList
        notifyWidgetUpdate()

        if (authManager.hasValidToken()) {
            scope.launch {
                val res = api.createTask(targetListId, newTask)
                res.onSuccess { created ->
                    val refreshed = _allTasks.value.map {
                        if (it.id == newTask.id) it.copy(id = created.id) else it
                    }
                    _allTasks.value = refreshed
                    notifyWidgetUpdate()
                }
            }
        }
        return newTask
    }

    fun toggleTaskCompletion(taskId: String) {
        val current = _allTasks.value.find { it.id == taskId } ?: return
        val newStatus = if (current.isCompleted) TaskStatus.NEEDS_ACTION else TaskStatus.COMPLETED
        val updated = current.copy(status = newStatus, updated = System.currentTimeMillis())

        _allTasks.value = _allTasks.value.map { if (it.id == taskId) updated else it }
        notifyWidgetUpdate()

        if (authManager.hasValidToken()) {
            scope.launch {
                api.updateTask(updated.listId, updated)
            }
        }
    }

    fun updateTask(task: TaskItem) {
        _allTasks.value = _allTasks.value.map { if (it.id == task.id) task else it }
        notifyWidgetUpdate()
        if (authManager.hasValidToken()) {
            scope.launch {
                api.updateTask(task.listId, task)
            }
        }
    }

    fun deleteTask(taskId: String) {
        val task = _allTasks.value.find { it.id == taskId } ?: return
        _allTasks.value = _allTasks.value.filter { it.id != taskId }
        notifyWidgetUpdate()

        val trashed = task.copy(deletedAt = System.currentTimeMillis())
        _trashTasks.value = listOf(trashed) + _trashTasks.value

        if (authManager.hasValidToken()) {
            scope.launch {
                api.deleteTask(task.listId, taskId)
            }
        }
    }

    fun restoreTask(taskId: String) {
        val task = _trashTasks.value.find { it.id == taskId } ?: return
        _trashTasks.value = _trashTasks.value.filter { it.id != taskId }

        val restored = task.copy(deletedAt = null, updated = System.currentTimeMillis())
        _allTasks.value = listOf(restored) + _allTasks.value

        if (authManager.hasValidToken()) {
            scope.launch {
                val res = api.createTask(restored.listId, restored)
                res.onSuccess { created ->
                    _allTasks.value = _allTasks.value.map {
                        if (it.id == restored.id) it.copy(id = created.id) else it
                    }
                }
            }
        }
    }

    fun trashAllCompletedTasks() {
        val completed = _allTasks.value.filter { it.isCompleted }
        if (completed.isEmpty()) return

        _allTasks.value = _allTasks.value.filter { !it.isCompleted }
        val now = System.currentTimeMillis()
        val trashedItems = completed.map { it.copy(deletedAt = now) }
        _trashTasks.value = trashedItems + _trashTasks.value

        if (authManager.hasValidToken()) {
            scope.launch {
                for (t in completed) {
                    api.deleteTask(t.listId, t.id)
                }
            }
        }
    }

    fun emptyTrash() {
        _trashTasks.value = emptyList()
    }

    companion object {
        val shared by lazy { TaskRepository() }
    }
}
