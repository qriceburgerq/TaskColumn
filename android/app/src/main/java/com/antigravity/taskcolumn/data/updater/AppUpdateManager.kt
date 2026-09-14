package com.antigravity.taskcolumn.data.updater

import android.content.Context
import android.content.Intent
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

data class UpdateInfo(
    val currentVersion: String,
    val latestVersion: String,
    val releaseNotes: String,
    val downloadUrl: String?,
    val hasUpdate: Boolean
)

class AppUpdateManager {
    private val client = OkHttpClient()
    private val repoOwner = "qriceburgerq"
    private val repoName = "TaskColumn"

    suspend fun checkUpdate(currentVersion: String = "1.0.1"): Result<UpdateInfo> = withContext(Dispatchers.IO) {
        try {
            val url = "https://api.github.com/repos/$repoOwner/$repoName/releases/latest"
            val request = Request.Builder()
                .url(url)
                .header("Accept", "application/vnd.github.v3+json")
                .build()

            val response = client.newCall(request).execute()
            val body = response.body?.string().orEmpty()

            if (!response.isSuccessful) {
                return@withContext Result.failure(Exception("目前暫無新版本發布 (HTTP ${response.code})"))
            }

            val json = JSONObject(body)
            val tagName = json.optString("tag_name", "").removePrefix("v").trim()
            val releaseNotes = json.optString("body", "修復已知問題並帶來效能優化。")

            // Find APK asset
            var apkUrl: String? = null
            val assets = json.optJSONArray("assets")
            if (assets != null) {
                for (i in 0 until assets.length()) {
                    val asset = assets.getJSONObject(i)
                    val name = asset.optString("name", "")
                    if (name.endsWith(".apk", ignoreCase = true)) {
                        apkUrl = asset.optString("browser_download_url", null)
                        break
                    }
                }
            }

            // If no direct asset, fallback to release HTML url
            if (apkUrl == null) {
                apkUrl = json.optString("html_url", null)
            }

            val hasUpdate = isNewerVersion(current = currentVersion, latest = tagName)

            Result.success(
                UpdateInfo(
                    currentVersion = currentVersion,
                    latestVersion = tagName.ifBlank { currentVersion },
                    releaseNotes = releaseNotes,
                    downloadUrl = apkUrl,
                    hasUpdate = hasUpdate
                )
            )
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    fun openDownloadUrl(context: Context, downloadUrl: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(downloadUrl)).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        context.startActivity(intent)
    }

    private fun isNewerVersion(current: String, latest: String): Boolean {
        if (latest.isBlank()) return false
        val currentParts = current.split(".").mapNotNull { it.toIntOrNull() }
        val latestParts = latest.split(".").mapNotNull { it.toIntOrNull() }

        val maxLen = maxOf(currentParts.size, latestParts.size)
        for (i in 0 until maxLen) {
            val c = currentParts.getOrElse(i) { 0 }
            val l = latestParts.getOrElse(i) { 0 }
            if (l > c) return true
            if (l < c) return false
        }
        return false
    }

    companion object {
        val shared by lazy { AppUpdateManager() }
    }
}
