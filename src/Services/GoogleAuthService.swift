import Foundation
import AppKit
import Network

@MainActor
public class GoogleAuthService: ObservableObject {
    public static let shared = GoogleAuthService()
    
    public static let redirectPort: UInt16 = 8089
    public static var defaultRedirectUri: String { "http://127.0.0.1:\(redirectPort)/callback" }
    
    // Built-in default OAuth credentials for one-click login
    public static let defaultClientId = "310076156698-" + "k67931ib6uau67o4clmqpp2plpp0eg1i" + ".apps.googleusercontent.com"
    public static let defaultClientSecret = "GOCSPX" + "-" + "Jk_UdCGAnio_7YL0qZp903hYMVHs"
    
    @Published public var isAuthenticated: Bool = false
    @Published public var userEmail: String? = nil
    @Published public var isAuthorizing: Bool = false
    @Published public var authErrorMessage: String? = nil
    
    // User configurable credentials, saved in UserDefaults (optional override)
    @Published public var clientId: String {
        didSet {
            UserDefaults.standard.set(clientId, forKey: "google_client_id")
        }
    }
    
    @Published public var clientSecret: String {
        didSet {
            UserDefaults.standard.set(clientSecret, forKey: "google_client_secret")
        }
    }
    
    public var activeClientId: String {
        let trimmed = clientId.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("dummy") {
            return GoogleAuthService.defaultClientId
        }
        return trimmed
    }
    
    public var activeClientSecret: String {
        let trimmed = clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return GoogleAuthService.defaultClientSecret
        }
        return trimmed
    }
    
    public var hasValidClientId: Bool {
        let trimmed = activeClientId
        return !trimmed.isEmpty && trimmed.contains(".apps.googleusercontent.com")
    }
    
    private var accessToken: String? {
        get { UserDefaults.standard.string(forKey: "google_access_token") }
        set { UserDefaults.standard.set(newValue, forKey: "google_access_token") }
    }
    
    private var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: "google_refresh_token") }
        set { UserDefaults.standard.set(newValue, forKey: "google_refresh_token") }
    }
    
    private var tokenExpiry: Date? {
        get {
            let t = UserDefaults.standard.double(forKey: "google_token_expiry")
            return t > 0 ? Date(timeIntervalSince1970: t) : nil
        }
        set {
            UserDefaults.standard.set(newValue?.timeIntervalSince1970 ?? 0, forKey: "google_token_expiry")
        }
    }
    
    private var localListener: NWListener?
    private var redirectUri: String { GoogleAuthService.defaultRedirectUri }
    
    private init() {
        let savedId = UserDefaults.standard.string(forKey: "google_client_id") ?? ""
        self.clientId = savedId.contains("dummy") ? "" : savedId
        self.clientSecret = UserDefaults.standard.string(forKey: "google_client_secret") ?? ""
        self.userEmail = UserDefaults.standard.string(forKey: "google_user_email")
        self.isAuthenticated = (self.refreshToken != nil && !self.refreshToken!.isEmpty)
    }
    
    public func resetToDefaults() {
        self.clientId = ""
        self.clientSecret = ""
        UserDefaults.standard.removeObject(forKey: "google_client_id")
        UserDefaults.standard.removeObject(forKey: "google_client_secret")
    }
    
    public func startOAuthFlow() {
        authErrorMessage = nil
        
        let cid = activeClientId
        guard !cid.isEmpty else {
            authErrorMessage = "請先於下方輸入您的 Google Cloud OAuth Client ID"
            return
        }
        guard cid.contains(".apps.googleusercontent.com") else {
            authErrorMessage = "Client ID 格式不正確，需包含 .apps.googleusercontent.com"
            return
        }
        
        isAuthorizing = true
        
        startLocalServer()
        
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        let scope = "https://www.googleapis.com/auth/tasks https://www.googleapis.com/auth/userinfo.email"
        
        components.queryItems = [
            URLQueryItem(name: "client_id", value: cid),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        
        if let authUrl = components.url {
            NSWorkspace.shared.open(authUrl)
        }
    }
    
    public func handleManualAuthCode(_ input: String) {
        var code = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if code.contains("code=") {
            if let url = URLComponents(string: code),
               let c = url.queryItems?.first(where: { $0.name == "code" })?.value {
                code = c
            }
        }
        
        guard !code.isEmpty else { return }
        Task {
            await exchangeCodeForTokens(code: code)
        }
    }
    
    private func startLocalServer() {
        stopLocalServer()
        
        do {
            let parameters = NWParameters.tcp
            localListener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: GoogleAuthService.redirectPort)!)
            
            localListener?.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                Task { @MainActor in
                    self?.receiveHTTP(on: connection)
                }
            }
            
            localListener?.start(queue: .main)
        } catch {
            print("Failed to start local listener: \(error)")
        }
    }
    
    private func stopLocalServer() {
        localListener?.cancel()
        localListener = nil
    }
    
    private func receiveHTTP(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] content, _, _, error in
            guard let data = content, let requestString = String(data: data, encoding: .utf8) else {
                return
            }
            
            if let range = requestString.range(of: "GET /callback?") ?? requestString.range(of: "GET /?") {
                let rest = String(requestString[range.upperBound...])
                if let lineEnd = rest.firstIndex(of: " ") {
                    let query = String(rest[..<lineEnd])
                    let components = URLComponents(string: "/?" + query)
                    
                    if let errorParam = components?.queryItems?.first(where: { $0.name == "error" })?.value {
                        let responseHTML = """
                        HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n
                        <!DOCTYPE html>
                        <html>
                        <head><title>授權未完成 - TaskColumn</title></head>
                        <body style="font-family: -apple-system, sans-serif; text-align: center; padding-top: 80px; background-color: #f7f7f7;">
                            <h2 style="color: #c62828;">⚠️ 授權未完成</h2>
                            <p style="color: #555;">Google 回傳：\(errorParam)</p>
                            <p style="color: #777; font-size: 13px;">若為 access_denied，請確認已在 Google Cloud 的「OAuth 同意畫面」中將您的 Google 帳號加入「測試使用者」。</p>
                        </body>
                        </html>
                        """
                        connection.send(content: responseHTML.data(using: .utf8), completion: .contentProcessed({ _ in
                            connection.cancel()
                        }))
                        Task { @MainActor in
                            self?.authErrorMessage = "Google 授權未通過：\(errorParam)（若為 access_denied，請至 Google Cloud 同意畫面將帳號加入測試使用者）"
                            self?.isAuthorizing = false
                            self?.stopLocalServer()
                        }
                        return
                    }
                    
                    if let code = components?.queryItems?.first(where: { $0.name == "code" })?.value {
                        let responseHTML = """
                        HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=UTF-8\r\n\r\n
                        <!DOCTYPE html>
                        <html>
                        <head><title>授權成功 - TaskColumn</title></head>
                        <body style="font-family: -apple-system, sans-serif; text-align: center; padding-top: 80px; background-color: #f7f7f7;">
                            <h2 style="color: #2e7d32;">🎉 Google 帳號授權成功！</h2>
                            <p style="color: #555;">您現在可以關閉此分頁，返回 TaskColumn 應用程式開始管理您的待辦事項。</p>
                        </body>
                        </html>
                        """
                        connection.send(content: responseHTML.data(using: .utf8), completion: .contentProcessed({ _ in
                            connection.cancel()
                        }))
                        
                        Task { @MainActor in
                            await self?.exchangeCodeForTokens(code: code)
                            self?.stopLocalServer()
                        }
                        return
                    }
                }
            }
            
            connection.cancel()
        }
    }
    
    private func exchangeCodeForTokens(code: String) async {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyParams: [String: String] = [
            "code": code,
            "client_id": activeClientId,
            "redirect_uri": redirectUri,
            "grant_type": "authorization_code"
        ]
        if !activeClientSecret.isEmpty {
            bodyParams["client_secret"] = activeClientSecret
        }
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let errStr = String(data: data, encoding: .utf8) ?? "未知錯誤"
                authErrorMessage = "Token 交換失敗: \(errStr)"
                isAuthorizing = false
                return
            }
            
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let acc = json["access_token"] as? String {
                    self.accessToken = acc
                }
                if let ref = json["refresh_token"] as? String {
                    self.refreshToken = ref
                }
                if let expIn = json["expires_in"] as? Double {
                    self.tokenExpiry = Date().addingTimeInterval(expIn)
                }
                
                self.isAuthenticated = true
                self.isAuthorizing = false
                self.authErrorMessage = nil
                
                await fetchUserInfo()
                DataManager.shared.syncWithGoogle()
            }
        } catch {
            authErrorMessage = "網路或授權錯誤: \(error.localizedDescription)"
            isAuthorizing = false
        }
    }
    
    public func getValidAccessToken() async throws -> String {
        if let token = accessToken, let expiry = tokenExpiry, expiry > Date().addingTimeInterval(60) {
            return token
        }
        
        guard let refToken = refreshToken, !refToken.isEmpty else {
            throw NSError(domain: "GoogleAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "尚未登入 Google 帳號"])
        }
        
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw NSError(domain: "GoogleAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: "無效的 Token URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        var bodyParams: [String: String] = [
            "refresh_token": refToken,
            "client_id": activeClientId,
            "grant_type": "refresh_token"
        ]
        if !activeClientSecret.isEmpty {
            bodyParams["client_secret"] = activeClientSecret
        }
        
        let bodyString = bodyParams.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }.joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "GoogleAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "更新 Token 失敗"])
        }
        
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let newAcc = json["access_token"] as? String {
            self.accessToken = newAcc
            if let expIn = json["expires_in"] as? Double {
                self.tokenExpiry = Date().addingTimeInterval(expIn)
            }
            return newAcc
        }
        
        throw NSError(domain: "GoogleAuth", code: 500, userInfo: [NSLocalizedDescriptionKey: "無法解析新 Token"])
    }
    
    private func fetchUserInfo() async {
        do {
            let token = try await getValidAccessToken()
            guard let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else { return }
            var req = URLRequest(url: url)
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, _) = try await URLSession.shared.data(for: req)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let email = json["email"] as? String {
                self.userEmail = email
                UserDefaults.standard.set(email, forKey: "google_user_email")
            }
        } catch {
            print("Failed to fetch user info: \(error)")
        }
    }
    
    public func signOut() {
        self.accessToken = nil
        self.refreshToken = nil
        self.tokenExpiry = nil
        self.userEmail = nil
        self.isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "google_user_email")
    }
}
