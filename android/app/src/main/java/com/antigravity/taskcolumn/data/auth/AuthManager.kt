package com.antigravity.taskcolumn.data.auth

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import com.antigravity.taskcolumn.TaskColumnApplication
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject

class AuthManager(context: Context = TaskColumnApplication.instance) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("taskcolumn_auth_prefs", Context.MODE_PRIVATE)
    private val client = OkHttpClient()

    private val _isAuthenticated = MutableStateFlow(hasValidToken())
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated

    private val _userEmail = MutableStateFlow(prefs.getString("user_email", null))
    val userEmail: StateFlow<String?> = _userEmail

    // Default Android Client ID (generated from Google Cloud Console for com.antigravity.taskcolumn)
    val defaultClientId = "310076156698-" + "9to80c1nsp7n36ncds9ic324nhimuo92" + ".apps.googleusercontent.com"
    val defaultClientSecret = ""
    val redirectUri = "com.antigravity.taskcolumn:/oauth2callback"

    fun getClientId(): String {
        return prefs.getString("custom_client_id", null) ?: defaultClientId
    }

    fun getClientSecret(): String {
        return prefs.getString("custom_client_secret", null) ?: defaultClientSecret
    }

    fun hasValidToken(): Boolean {
        return prefs.getString("access_token", null) != null
    }

    fun getAccessToken(): String? {
        return prefs.getString("access_token", null)
    }

    fun buildAuthUrl(): String {
        return Uri.parse("https://accounts.google.com/o/oauth2/v2/auth").buildUpon()
            .appendQueryParameter("client_id", getClientId())
            .appendQueryParameter("redirect_uri", redirectUri)
            .appendQueryParameter("response_type", "code")
            .appendQueryParameter("scope", "https://www.googleapis.com/auth/tasks https://www.googleapis.com/auth/userinfo.email")
            .appendQueryParameter("access_type", "offline")
            .appendQueryParameter("prompt", "consent")
            .build().toString()
    }

    suspend fun exchangeCodeForToken(code: String): Result<Unit> = withContext(Dispatchers.IO) {
        try {
            val bodyBuilder = FormBody.Builder()
                .add("code", code)
                .add("client_id", getClientId())
                .add("redirect_uri", redirectUri)
                .add("grant_type", "authorization_code")

            val secret = getClientSecret()
            if (secret.isNotBlank()) {
                bodyBuilder.add("client_secret", secret)
            }

            val request = Request.Builder()
                .url("https://oauth2.googleapis.com/token")
                .post(bodyBuilder.build())
                .build()

            val response = client.newCall(request).execute()
            val responseText = response.body?.string().orEmpty()

            if (response.isSuccessful) {
                val json = JSONObject(responseText)
                val accessToken = json.getString("access_token")
                val refreshToken = json.optString("refresh_token", null)
                val expiresIn = json.optLong("expires_in", 3600)

                saveTokens(accessToken, refreshToken, expiresIn)
                fetchUserProfile(accessToken)

                _isAuthenticated.value = true
                Result.success(Unit)
            } else {
                Result.failure(Exception("Token exchange failed: $responseText"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
    }

    private suspend fun fetchUserProfile(accessToken: String) = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder()
                .url("https://www.googleapis.com/oauth2/v2/userinfo")
                .header("Authorization", "Bearer $accessToken")
                .build()
            val resp = client.newCall(req).execute()
            if (resp.isSuccessful) {
                val json = JSONObject(resp.body?.string().orEmpty())
                val email = json.optString("email", null)
                if (email != null) {
                    prefs.edit().putString("user_email", email).apply()
                    _userEmail.value = email
                }
            }
        } catch (_: Exception) {}
    }

    private fun saveTokens(accessToken: String, refreshToken: String?, expiresIn: Long) {
        val expiryTime = System.currentTimeMillis() + (expiresIn * 1000)
        val editor = prefs.edit()
            .putString("access_token", accessToken)
            .putLong("token_expiry", expiryTime)

        if (refreshToken != null) {
            editor.putString("refresh_token", refreshToken)
        }
        editor.apply()
    }

    fun signOut() {
        prefs.edit()
            .remove("access_token")
            .remove("refresh_token")
            .remove("token_expiry")
            .remove("user_email")
            .apply()
        _isAuthenticated.value = false
        _userEmail.value = null
    }

    companion object {
        val shared by lazy { AuthManager() }
    }
}
