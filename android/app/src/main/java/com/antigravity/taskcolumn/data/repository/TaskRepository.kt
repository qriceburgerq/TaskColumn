package com.antigravity.taskcolumn.data.repository

import android.content.Context
import com.antigravity.taskcolumn.TaskColumnApplication
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
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.util.UUID

class TaskRepository(
    private val api: GoogleTasksApi = GoogleTasksApi(),
    private val authManager: AuthManager = AuthManager.shared,
    private val context: Context = TaskColumnApplication.instance,
    private val scope: CoroutineScope = CoroutineScope(Dispatchers.Main)
) {
    private val prefs = context.getSharedPreferences("taskcolumn_cache_prefs", Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    private val _allTasks = MutableStateFlow<List<TaskItem>>(loadCachedTasks())
    val allTasks: StateFlow<List<TaskItem>> = _allTasks.asStateFlow()

    private val _lists = MutableStateFlow<List<TaskList>>(loadCachedLists())
    val lists: StateFlow<List<TaskList>> = _lists.asStateFlow()

    private val _trashTasks = MutableStateFlow<List<TaskItem>>(emptyList())
    val trashTasks: StateFlow<List<TaskItem>> = _trashTasks.asStateFlow()

    private val _selectedFilter = MutableStateFlow<SmartFilterType>(SmartFilterType.Pending)
    val selectedFilter: StateFlow<SmartFilterType> = _selectedFilter.asStateFlow()

    private val _isSyncing = MutableStateFlow(false)
    val isSyncing: StateFlow<Boolean> = _isSyncing.asStateFlow()

    private val _lastSyncTime = MutableStateFlow<Long?>(prefs.getLong("last_sync_time", 0).let { if (it > 0) it else null })
    val lastSyncTime: StateFlow<Long?> = _lastSyncTime.asStateFlow()

    private val _searchQuery = MutableStateFlow("")
    val searchQuery: StateFlow<String> = _searchQuery.asStateFlow()

    private fun loadCachedTasks(): List<TaskItem> {
        val raw = prefs.getString("cached_tasks", null)
        if (!raw.isNullOrBlank()) {
            try {
                return json.decodeFromString<List<TaskItem>>(raw)
            } catch (_: Exception) {}
        }
        return listOf(
            TaskItem(
                id = UUID.randomUUID().toString(),
                listId = "@default",
                title = "歡迎使用 TaskColumn 手機版！",
                notes = "登入 Google 帳號後，所有待辦與 Mac 桌面端即時無縫雙向同步。",
                due = System.currentTimeMillis()
            ),
            TaskItem(
                id = UUID.randomUUID().toString(),
                listId = "@default",
                title = "點選右下方「+」快速新增待辦事項",
                notes = "支援設定自訂到期日與詳細備忘筆記。"
            )
        )
    }

    private fun saveTasksToCache(tasks: List<TaskItem>) {
        try {
            val raw = json.encodeToString(tasks)
            prefs.edit().putString("cached_tasks", raw).apply()
        } catch (_: Exception) {}
    }

    private fun loadCachedLists(): List<TaskList> {
        val raw = prefs.getString("cached_lists", null)
        if (!raw.isNullOrBlank()) {
            try {
                val parsed = json.decodeFromString<List<TaskList>>(raw)
                if (parsed.isNotEmpty()) return parsed
            } catch (_: Exception) {}
        }
        return listOf(TaskList("@default", "主要待辦"))
    }

    private fun saveListsToCache(lists: List<TaskList>) {
        try {
            val raw = json.encodeToString(lists)
            prefs.edit().putString("cached_lists", raw).apply()
        } catch (_: Exception) {}
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
                saveListsToCache(remoteLists)
                val collected = mutableListOf<TaskItem>()
                for (l in remoteLists) {
                    val tasksResult = api.fetchTasks(l.id)
                    tasksResult.onSuccess { tasks ->
                        collected.addAll(tasks)
                    }
                }

                // Protect offline-created tasks:
                // Any task in current _allTasks whose id is NOT in collected (e.g. UUID id)
                // should be uploaded to Google Tasks, not lost!
                val remoteIds = collected.map { it.id }.toSet()
                val unsyncedLocal = _allTasks.value.filter { it.id !in remoteIds && !it.isCompleted }
                val targetListId = remoteLists.firstOrNull()?.id ?: "@default"

                for (localItem in unsyncedLocal) {
                    val res = api.createTask(targetListId, localItem)
                    res.onSuccess { created ->
                        collected.add(0, created)
                    }.onFailure {
                        collected.add(0, localItem)
                    }
                }

                _allTasks.value = collected
                val now = System.currentTimeMillis()
                _lastSyncTime.value = now
                prefs.edit().putLong("last_sync_time", now).apply()
                notifyWidgetUpdate()
            }
            _isSyncing.value = false
        }
    }

    fun addTaskList(title: String) {
        val trimmed = title.trim()
        if (trimmed.isBlank()) return
        val tempId = UUID.randomUUID().toString()
        val newList = TaskList(id = tempId, title = trimmed)
        val updatedLists = _lists.value + newList
        _lists.value = updatedLists
        saveListsToCache(updatedLists)

        if (authManager.hasValidToken()) {
            scope.launch {
                val res = api.createTaskList(trimmed)
                res.onSuccess { created ->
                    val replaced = _lists.value.map { if (it.id == tempId) created else it }
                    _lists.value = replaced
                    saveListsToCache(replaced)
                    val updatedTasks = _allTasks.value.map {
                        if (it.listId == tempId) it.copy(listId = created.id) else it
                    }
                    _allTasks.value = updatedTasks
                    notifyWidgetUpdate()
                }
            }
        }
    }

    fun deleteTaskList(listId: String) {
        if ((listId == "@default" || listId == "default") && _lists.value.size <= 1) return
        val updatedLists = _lists.value.filter { it.id != listId }
        _lists.value = if (updatedLists.isEmpty()) listOf(TaskList("@default", "主要待辦")) else updatedLists
        saveListsToCache(_lists.value)

        // Move tasks to trash or remove
        val toTrash = _allTasks.value.filter { it.listId == listId }
        _trashTasks.value = toTrash + _trashTasks.value
        _allTasks.value = _allTasks.value.filter { it.listId != listId }
        notifyWidgetUpdate()

        if ((_selectedFilter.value as? SmartFilterType.CustomList)?.listId == listId) {
            _selectedFilter.value = SmartFilterType.Pending
        }

        if (authManager.hasValidToken()) {
            scope.launch {
                api.deleteTaskList(listId)
            }
        }
    }

    private fun notifyWidgetUpdate() {
        saveTasksToCache(_allTasks.value)
        try {
            com.antigravity.taskcolumn.widget.TaskWidgetProvider.updateAllWidgets(
                com.antigravity.taskcolumn.TaskColumnApplication.instance
            )
        } catch (_: Exception) {}
    }

    fun addTask(title: String, notes: String? = null, due: Long? = null, listId: String? = null): TaskItem {
        val targetListId = listId ?: _lists.value.firstOrNull()?.id ?: "@default"
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
