package com.antigravity.taskcolumn.data.auth

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import com.antigravity.taskcolumn.TaskColumnApplication
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.FormBody
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.util.concurrent.TimeUnit

class AuthManager(context: Context = TaskColumnApplication.instance) {
    private val prefs: SharedPreferences =
        context.getSharedPreferences("taskcolumn_auth_prefs", Context.MODE_PRIVATE)

    private val exchangeMutex = Mutex()
    @Volatile
    private var lastExchangedCode: String? = null

    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .retryOnConnectionFailure(true)
        .build()

    private val scope = CoroutineScope(Dispatchers.IO)

    private val _isAuthenticated = MutableStateFlow(hasValidToken())
    val isAuthenticated: StateFlow<Boolean> = _isAuthenticated

    private val _userEmail = MutableStateFlow(prefs.getString("user_email", null))
    val userEmail: StateFlow<String?> = _userEmail

    private val _isAuthorizing = MutableStateFlow(false)
    val isAuthorizing: StateFlow<Boolean> = _isAuthorizing

    private val _authErrorMessage = MutableStateFlow<String?>(null)
    val authErrorMessage: StateFlow<String?> = _authErrorMessage

    // Shared default Desktop OAuth credentials (same as macOS, supports loopback on port 8089)
    val defaultClientId = "310076156698-" + "k67931ib6uau67o4clmqpp2plpp0eg1i" + ".apps.googleusercontent.com"
    val defaultClientSecret = "GOCSPX" + "-" + "Jk_UdCGAnio_7YL0qZp903hYMVHs"
    val redirectPort = 8089
    val redirectUri = "http://127.0.0.1:$redirectPort/callback"
    val fallbackSchemeRedirectUri = "com.antigravity.taskcolumn:/oauth2callback"

    private var serverJob: Job? = null
    private var serverSocket: ServerSocket? = null

    fun getClientId(): String {
        val custom = prefs.getString("custom_client_id", null)?.trim()
        return if (!custom.isNullOrBlank()) custom else defaultClientId
    }

    fun getClientSecret(): String {
        val custom = prefs.getString("custom_client_secret", null)?.trim()
        return if (!custom.isNullOrBlank()) custom else defaultClientSecret
    }

    fun setCustomCredentials(clientId: String?, clientSecret: String?) {
        val editor = prefs.edit()
        if (clientId.isNullOrBlank()) editor.remove("custom_client_id") else editor.putString("custom_client_id", clientId.trim())
        if (clientSecret.isNullOrBlank()) editor.remove("custom_client_secret") else editor.putString("custom_client_secret", clientSecret.trim())
        editor.apply()
    }

    fun hasCustomCredentials(): Boolean {
        return !prefs.getString("custom_client_id", null).isNullOrBlank()
    }

    fun clearCustomCredentials() {
        prefs.edit().remove("custom_client_id").remove("custom_client_secret").apply()
    }

    fun hasValidToken(): Boolean {
        return prefs.getString("access_token", null) != null || prefs.getString("refresh_token", null) != null
    }

    fun getAccessToken(): String? {
        return prefs.getString("access_token", null)
    }

    /**
     * Retrieves a valid access token. If the current token is close to expiry or expired,
     * automatically refreshes it using the refresh token.
     */
    suspend fun getValidAccessToken(): String? = withContext(Dispatchers.IO) {
        val token = prefs.getString("access_token", null)
        val expiry = prefs.getLong("token_expiry", 0)
        val now = System.currentTimeMillis()

        // If current token is valid for at least 60 more seconds, return it
        if (!token.isNullOrBlank() && expiry > now + 60_000) {
            return@withContext token
        }

        // Try refreshing token
        val refreshToken = prefs.getString("refresh_token", null)
        if (refreshToken.isNullOrBlank()) {
            return@withContext if (expiry > now) token else null
        }

        val refreshResult = refreshAccessToken(refreshToken)
        if (refreshResult.isSuccess) {
            return@withContext refreshResult.getOrNull()
        }

        // If refresh failed and token expired, return null to force re-auth
        return@withContext if (expiry > now) token else null
    }

    private suspend fun refreshAccessToken(refreshToken: String): Result<String> = withContext(Dispatchers.IO) {
        try {
            val bodyBuilder = FormBody.Builder()
                .add("refresh_token", refreshToken)
                .add("client_id", getClientId())
                .add("grant_type", "refresh_token")

            val secret = getClientSecret()
            if (secret.isNotBlank()) {
                bodyBuilder.add("client_secret", secret)
            }

            val request = Request.Builder()
                .url("https://oauth2.googleapis.com/token")
                .post(bodyBuilder.build())
                .build()

            val response = client.newCall(request).execute()
            val text = response.body?.string().orEmpty()

            if (response.isSuccessful) {
                val json = JSONObject(text)
                val newAccessToken = json.getString("access_token")
                val expiresIn = json.optLong("expires_in", 3600)
                val newRefreshToken = json.optString("refresh_token", null)

                saveTokens(newAccessToken, newRefreshToken, expiresIn)
                _isAuthenticated.value = true
                Result.success(newAccessToken)
            } else {
                // If token is invalid or revoked, auto sign out to clear stale credentials
                if (response.code in 400..401) {
                    signOut()
                    _authErrorMessage.value = "Google 登入憑證已失效，請重新點擊登入"
                }
                Result.failure(Exception("Token refresh failed: $text"))
            }
        } catch (e: Exception) {
            Result.failure(e)
        }
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

    /**
     * Starts a lightweight local HTTP server listening on 127.0.0.1:8089.
     * When Chrome receives the callback, the server redirects it to com.antigravity.taskcolumn
     * so Android automatically brings TaskColumn to the FOREGROUND before token exchange.
     */
    fun startLocalServer(onAuthCompleted: (Boolean, String?) -> Unit) {
        stopLocalServer()
        _isAuthorizing.value = true
        _authErrorMessage.value = null

        serverJob = scope.launch {
            try {
                val server = ServerSocket()
                server.reuseAddress = true
                server.bind(InetSocketAddress("127.0.0.1", redirectPort))
                serverSocket = server

                val socket = server.accept()
                val reader = BufferedReader(InputStreamReader(socket.getInputStream()))
                val requestLine = reader.readLine().orEmpty()

                var authCode: String? = null
                var authError: String? = null

                if (requestLine.contains("GET ")) {
                    val pathAndQuery = requestLine.substringAfter("GET ").substringBefore(" HTTP")
                    val uri = Uri.parse("http://127.0.0.1:$redirectPort$pathAndQuery")
                    authCode = uri.getQueryParameter("code")
                    authError = uri.getQueryParameter("error")
                }

                val responseHtml = if (!authCode.isNullOrEmpty()) {
                    """
                    HTTP/1.1 200 OK
                    Content-Type: text/html; charset=UTF-8

                    <!DOCTYPE html>
                    <html>
                    <head>
                        <meta charset="utf-8">
                        <meta http-equiv="refresh" content="0;url=com.antigravity.taskcolumn:/oauth2callback?code=$authCode">
                        <script>
                            window.location.href = "com.antigravity.taskcolumn:/oauth2callback?code=$authCode";
                        </script>
                    </head>
                    <body style="font-family: sans-serif; text-align: center; padding-top: 60px; background-color: #121212; color: #fff;">
                        <h2 style="color: #4CAF50;">🎉 授權成功，正在返回 TaskColumn...</h2>
                        <p style="color: #aaa;"><a href="com.antigravity.taskcolumn:/oauth2callback?code=$authCode" style="color: #0A84FF; font-size: 16px;">點擊此處立即返回應用程式</a></p>
                    </body>
                    </html>
                    """.trimIndent()
                } else {
                    """
                    HTTP/1.1 200 OK
                    Content-Type: text/html; charset=UTF-8

                    <!DOCTYPE html>
                    <html>
                    <head><meta charset="utf-8"><title>授權未完成 - TaskColumn</title></head>
                    <body style="font-family: sans-serif; text-align: center; padding-top: 60px; background-color: #121212; color: #fff;">
                        <h2 style="color: #F44336;">⚠️ 授權未完成</h2>
                        <p style="color: #aaa;">錯誤訊息：${authError ?: "未取得授權碼"}</p>
                    </body>
                    </html>
                    """.trimIndent()
                }

                socket.getOutputStream().write(responseHtml.toByteArray(Charsets.UTF_8))
                socket.getOutputStream().flush()
                socket.close()
                server.close()

                if (!authCode.isNullOrEmpty()) {
                    // Give Chrome a short moment to launch com.antigravity.taskcolumn intent
                    // which brings TaskColumn to foreground with full network permission
                    delay(300)
                    val result = exchangeCodeForToken(authCode, redirectUri)
                    withContext(Dispatchers.Main) {
                        _isAuthorizing.value = false
                        if (result.isSuccess) {
                            onAuthCompleted(true, null)
                        } else {
                            val msg = result.exceptionOrNull()?.message ?: "Token 交換失敗"
                            _authErrorMessage.value = msg
                            onAuthCompleted(false, msg)
                        }
                    }
                } else {
                    withContext(Dispatchers.Main) {
                        _isAuthorizing.value = false
                        val msg = authError ?: "授權已取消"
                        _authErrorMessage.value = msg
                        onAuthCompleted(false, msg)
                    }
                }
            } catch (_: Exception) {
                withContext(Dispatchers.Main) {
                    _isAuthorizing.value = false
                }
            } finally {
                stopLocalServer()
            }
        }
    }

    fun stopLocalServer() {
        try {
            serverSocket?.close()
        } catch (_: Exception) {}
        serverSocket = null
        serverJob?.cancel()
        serverJob = null
    }

    /**
     * Handles manual input of authorization code or redirected URL.
     */
    suspend fun handleManualAuthCode(input: String): Result<Unit> = withContext(Dispatchers.IO) {
        var code = input.trim()
        var usedRedirectUri = redirectUri

        if (code.contains("code=")) {
            val uri = Uri.parse(if (code.startsWith("http") || code.startsWith("com.antigravity")) code else "http://dummy?$code")
            code = uri.getQueryParameter("code") ?: code
            if (code.startsWith("com.antigravity")) {
                usedRedirectUri = fallbackSchemeRedirectUri
            }
        }

        if (code.isBlank()) {
            return@withContext Result.failure(Exception("授權碼不能為空"))
        }

        exchangeCodeForToken(code, usedRedirectUri)
    }

    /**
     * Exchanges auth code for access & refresh tokens with automatic retries.
     */
    suspend fun exchangeCodeForToken(code: String, customRedirectUri: String? = null): Result<Unit> = withContext(Dispatchers.IO) {
        exchangeMutex.withLock {
            if (lastExchangedCode == code && hasValidToken()) {
                return@withLock Result.success(Unit)
            }

            val targetRedirect = customRedirectUri ?: redirectUri
            val bodyBuilder = FormBody.Builder()
                .add("code", code)
                .add("client_id", getClientId())
                .add("redirect_uri", targetRedirect)
                .add("grant_type", "authorization_code")

            val secret = getClientSecret()
            if (secret.isNotBlank()) {
                bodyBuilder.add("client_secret", secret)
            }

            val request = Request.Builder()
                .url("https://oauth2.googleapis.com/token")
                .post(bodyBuilder.build())
                .build()

            var lastException: Exception? = null
            for (attempt in 1..3) {
                try {
                    val response = client.newCall(request).execute()
                    val responseText = response.body?.string().orEmpty()

                    if (response.isSuccessful) {
                        val json = JSONObject(responseText)
                        val accessToken = json.getString("access_token")
                        val refreshToken = json.optString("refresh_token", null)
                        val expiresIn = json.optLong("expires_in", 3600)

                        saveTokens(accessToken, refreshToken, expiresIn)
                        lastExchangedCode = code
                        fetchUserProfile(accessToken)

                        _isAuthenticated.value = true
                        _authErrorMessage.value = null
                        return@withLock Result.success(Unit)
                    } else {
                        val errMsg = "Token exchange failed: $responseText"
                        _authErrorMessage.value = errMsg
                        return@withLock Result.failure(Exception(errMsg))
                    }
                } catch (e: Exception) {
                    lastException = e
                    if (attempt < 3) {
                        delay(800L * attempt)
                    }
                }
            }

            val err = lastException ?: Exception("網路連線失敗，請檢查網路後重試")
            _authErrorMessage.value = err.message
            Result.failure(err)
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

        if (!refreshToken.isNullOrBlank()) {
            editor.putString("refresh_token", refreshToken)
        }
        editor.apply()
    }

    fun signOut() {
        stopLocalServer()
        lastExchangedCode = null
        prefs.edit()
            .remove("access_token")
            .remove("refresh_token")
            .remove("token_expiry")
            .remove("user_email")
            .apply()
        _isAuthenticated.value = false
        _userEmail.value = null
        _authErrorMessage.value = null
    }

    companion object {
        val shared by lazy { AuthManager() }
    }
}
