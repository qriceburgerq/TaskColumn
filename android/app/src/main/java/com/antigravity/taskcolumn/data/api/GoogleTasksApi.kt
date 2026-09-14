package com.antigravity.taskcolumn.data.api

import com.antigravity.taskcolumn.data.auth.AuthManager
import com.antigravity.taskcolumn.data.model.TaskItem
import com.antigravity.taskcolumn.data.model.TaskList
import com.antigravity.taskcolumn.data.model.TaskStatus
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

class GoogleTasksApi(
    private val authManager: AuthManager = AuthManager.shared
) {
    private val client = OkHttpClient()
    private val baseUrl = "https://tasks.googleapis.com/tasks/v1"
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()

    private val rfc3339Format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    private fun getAuthHeader(): String? {
        val token = authManager.getAccessToken() ?: return null
        return "Bearer $token"
    }

    suspend fun fetchTaskLists(): Result<List<TaskList>> = withContext(Dispatchers.IO) {
        try {
            val auth = getAuthHeader() ?: return@withContext Result.failure(Exception("尚未登入 Google 帳號"))
            val req = Request.Builder()
                .url("$baseUrl/users/@me/lists")
                .header("Authorization", auth)
                .build()

            val resp = client.newCall(req).execute()
            val text = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                return@withContext Result.failure(Exception("撈取清單失敗: ${resp.code} $text"))
            }

            val json = JSONObject(text)
            val items = json.optJSONArray("items") ?: JSONArray()
            val lists = mutableListOf<TaskList>()
            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                lists.add(
                    TaskList(
                        id = item.getString("id"),
                        title = item.getString("title")
                    )
                )
            }
            Result.success(lists)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun fetchTasks(listId: String): Result<List<TaskItem>> = withContext(Dispatchers.IO) {
        try {
            val auth = getAuthHeader() ?: return@withContext Result.failure(Exception("尚未登入 Google 帳號"))
            val req = Request.Builder()
                .url("$baseUrl/lists/$listId/tasks?showCompleted=true&showHidden=true")
                .header("Authorization", auth)
                .build()

            val resp = client.newCall(req).execute()
            val text = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                return@withContext Result.failure(Exception("撈取任務失敗: ${resp.code} $text"))
            }

            val json = JSONObject(text)
            val items = json.optJSONArray("items") ?: JSONArray()
            val tasks = mutableListOf<TaskItem>()
            for (i in 0 until items.length()) {
                val item = items.getJSONObject(i)
                val statusStr = item.optString("status", "needsAction")
                val status = if (statusStr == "completed") TaskStatus.COMPLETED else TaskStatus.NEEDS_ACTION
                val dueStr = item.optString("due", null)
                val dueTime = if (!dueStr.isNullOrEmpty()) {
                    try { rfc3339Format.parse(dueStr)?.time } catch (_: Exception) { null }
                } else null

                tasks.add(
                    TaskItem(
                        id = item.getString("id"),
                        listId = listId,
                        title = item.optString("title", "未命名待辦"),
                        notes = item.optString("notes", null),
                        due = dueTime,
                        status = status,
                        parent = item.optString("parent", null)
                    )
                )
            }
            Result.success(tasks)
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun createTask(listId: String, task: TaskItem): Result<TaskItem> = withContext(Dispatchers.IO) {
        try {
            val auth = getAuthHeader() ?: return@withContext Result.failure(Exception("尚未登入"))
            val jsonBody = JSONObject().apply {
                put("title", task.title)
                if (!task.notes.isNullOrEmpty()) put("notes", task.notes)
                if (task.due != null) {
                    put("due", rfc3339Format.format(Date(task.due!!)))
                }
                put("status", task.status.value)
            }

            val req = Request.Builder()
                .url("$baseUrl/lists/$listId/tasks")
                .header("Authorization", auth)
                .post(jsonBody.toString().toRequestBody(jsonMediaType))
                .build()

            val resp = client.newCall(req).execute()
            val text = resp.body?.string().orEmpty()
            if (resp.isSuccessful) {
                val resObj = JSONObject(text)
                task.id = resObj.getString("id")
                Result.success(task)
            } else {
                Result.failure(Exception("建立任務失敗: $text"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun updateTask(listId: String, task: TaskItem): Result<TaskItem> = withContext(Dispatchers.IO) {
        try {
            val auth = getAuthHeader() ?: return@withContext Result.failure(Exception("尚未登入"))
            val jsonBody = JSONObject().apply {
                put("id", task.id)
                put("title", task.title)
                put("notes", task.notes ?: "")
                if (task.due != null) {
                    put("due", rfc3339Format.format(Date(task.due!!)))
                } else {
                    put("due", JSONObject.NULL)
                }
                put("status", task.status.value)
            }

            val req = Request.Builder()
                .url("$baseUrl/lists/$listId/tasks/${task.id}")
                .header("Authorization", auth)
                .put(jsonBody.toString().toRequestBody(jsonMediaType))
                .build()

            val resp = client.newCall(req).execute()
            if (resp.isSuccessful) {
                Result.success(task)
            } else {
                Result.failure(Exception("更新任務失敗: ${resp.body?.string()}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    suspend fun deleteTask(listId: String, taskId: String): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val auth = getAuthHeader() ?: return@withContext Result.failure(Exception("尚未登入"))
            val req = Request.Builder()
                .url("$baseUrl/lists/$listId/tasks/$taskId")
                .header("Authorization", auth)
                .delete()
                .build()

            val resp = client.newCall(req).execute()
            if (resp.isSuccessful) {
                Result.success(Unit)
            } else {
                Result.failure(Exception("刪除任務失敗: ${resp.code}"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }
}
