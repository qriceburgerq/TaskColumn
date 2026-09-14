import SwiftUI
import AppKit

public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authService = GoogleAuthService.shared
    @ObservedObject private var dataManager = DataManager.shared
    @ObservedObject private var hotkeyManager = HotkeyManager.shared
    @ObservedObject private var menuBarController = MenuBarController.shared
    
    @State private var manualCodeInput: String = ""
    @State private var copiedRedirectUri: Bool = false
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("偏好設定")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Button("完成") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    // MARK: - Section 1: Google Account Integration
                    googleAccountSection
                    
                    Divider()
                    
                    // MARK: - Section 2: Font Scaling / Text Size
                    fontScalingSection
                    
                    Divider()
                    
                    // MARK: - Section 3: Customizable Global Hotkey
                    hotkeySection
                    
                    Divider()
                    
                    // MARK: - Section 4: macOS Menu Bar Status Item
                    menuBarSection
                    
                    Divider()
                    
                    // MARK: - Section 5: App Version & About
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TaskColumn for Google Tasks")
                                .font(.system(size: 12, weight: .bold))
                            Text("版本 v1.1.0 (原生 macOS Swift 6 架構)")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 640)
    }
    
    // MARK: - Google Account Section
    
    private var googleAccountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Google Tasks 雲端同步", systemImage: "cloud")
                .font(.system(size: 14, weight: .bold))
            
            if authService.isAuthenticated {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 20))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("已成功連結 Google 帳號")
                                .font(.system(size: 13, weight: .semibold))
                            if let email = authService.userEmail {
                                Text(email)
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button("立即同步") {
                            dataManager.syncWithGoogle()
                        }
                        .buttonStyle(BorderedButtonStyle())
                        
                        Button("登出") {
                            authService.signOut()
                        }
                        .foregroundColor(.red)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(8)
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // Ready-to-use card
                    VStack(alignment: .leading, spacing: 12) {
                        Text("已為您內建專用 Google OAuth 桌面憑證。點擊下方按鈕將開啟瀏覽器，完成授權後即可直接雙向同步 Google Tasks。")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 12) {
                            Button(action: {
                                authService.startOAuthFlow()
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: "globe")
                                    Text("使用 Google 帳號一鍵登入")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(BorderedProminentButtonStyle())
                            .disabled(authService.isAuthorizing || !authService.hasValidClientId)
                            
                            if authService.isAuthorizing {
                                ProgressView().controlSize(.small)
                                Text("正在等待瀏覽器授權...").font(.caption).foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    if let err = authService.authErrorMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.system(size: 12))
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        .padding(8)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(6)
                    }
                    
                    // Advanced Custom Credentials (Collapsible)
                    DisclosureGroup("進階設定：自訂 Google Cloud 憑證") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("預設使用內建憑證。若您有自己的 Google Cloud 專案，可於此輸入自訂憑證覆蓋：")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("OAuth 2.0 Client ID")
                                        .font(.system(size: 11, weight: .semibold))
                                    Spacer()
                                    Button("開啟 Google Cloud 控制台") {
                                        if let url = URL(string: "https://console.cloud.google.com/apis/credentials") {
                                            NSWorkspace.shared.open(url)
                                        }
                                    }
                                    .font(.system(size: 10))
                                    .buttonStyle(PlainButtonStyle())
                                    .foregroundColor(.accentColor)
                                }
                                
                                TextField("預設已啟用內建 ID（填入可覆蓋）", text: $authService.clientId)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.system(size: 11))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Client Secret (選填)")
                                    .font(.system(size: 11, weight: .semibold))
                                SecureField("預設已啟用內建 Secret（填入可覆蓋）", text: $authService.clientSecret)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.system(size: 11))
                            }
                            
                            HStack(spacing: 8) {
                                Text("重新導向 URI：")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                Text(GoogleAuthService.defaultRedirectUri)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.primary)
                                
                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(GoogleAuthService.defaultRedirectUri, forType: .string)
                                    copiedRedirectUri = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        copiedRedirectUri = false
                                    }
                                }) {
                                    Image(systemName: copiedRedirectUri ? "checkmark" : "doc.on.doc")
                                        .font(.system(size: 11))
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("複製重新導向 URI")
                                
                                if copiedRedirectUri {
                                    Text("已複製").font(.caption2).foregroundColor(.green)
                                }
                                
                                Spacer()
                                
                                if !authService.clientId.isEmpty || !authService.clientSecret.isEmpty {
                                    Button("還原預設憑證") {
                                        authService.resetToDefaults()
                                    }
                                    .font(.system(size: 10))
                                }
                            }
                            .padding(.top, 2)
                        }
                        .padding(10)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                        .cornerRadius(6)
                    }
                    
                    // Manual authorization code fallback
                    DisclosureGroup("備用方案：手動授權碼回填") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("若本地 8089 端口被佔用或瀏覽器未自動回呼，可將瀏覽器網址列跳轉後的網址或 code= 貼於此處：")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            
                            HStack {
                                TextField("貼上 code=... 或授權跳轉網址", text: $manualCodeInput)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .font(.system(size: 11))
                                Button("送出") {
                                    authService.handleManualAuthCode(manualCodeInput)
                                }
                                .disabled(manualCodeInput.isEmpty)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(8)
            }
        }
    }
    
    // MARK: - Font Scaling Section
    
    private var fontScalingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("字體大小與介面縮放比例", systemImage: "textformat.size")
                .font(.system(size: 14, weight: .bold))
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("目前字體比例：")
                        .font(.system(size: 12))
                    Text("\(Int(round(dataManager.fontScale * 100)))%")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.accentColor)
                    
                    Spacer()
                    
                    Button("重設預設 (100%)") {
                        dataManager.resetZoom()
                    }
                    .controlSize(.small)
                }
                
                // Slider
                Slider(value: $dataManager.fontScale, in: 0.8...1.5, step: 0.05)
                
                // Preset Buttons
                let presetScales: [Double] = [0.8, 0.9, 1.0, 1.1, 1.25, 1.5]
                HStack(spacing: 8) {
                    ForEach(presetScales, id: \.self) { (scale: Double) in
                        let percent = Int(round(scale * 100))
                        let isSelected = abs(dataManager.fontScale - scale) < 0.02
                        if isSelected {
                            Button("\(percent)%") {
                                dataManager.setZoom(scale)
                            }
                            .controlSize(.small)
                            .buttonStyle(BorderedProminentButtonStyle())
                        } else {
                            Button("\(percent)%") {
                                dataManager.setZoom(scale)
                            }
                            .controlSize(.small)
                            .buttonStyle(BorderedButtonStyle())
                        }
                    }
                }
                
                // Live Font Preview Card
                VStack(alignment: .leading, spacing: 6) {
                    Text("即時字級預覽")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .font(.appScale(14))
                        Text("完成季度專案規劃與備忘筆記整理")
                            .font(.appScale(13, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        Text("今天")
                            .font(.appScale(10, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12))
                            .foregroundColor(.orange)
                            .cornerRadius(4)
                    }
                    .padding(8)
                    .background(Color(NSColor.windowBackgroundColor))
                    .cornerRadius(6)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(6)
                
                Text("💡 提示：調整字體比例僅動態縮放文字大小，整體視窗幾何與各欄位邊界會自動調節，絕不產生截斷或溢出。您也可以在日常使用中隨時按下 ⌘ + 與 ⌘ - 進行微調，按 ⌘ 0 恢復 100%。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Hotkey Section
    
    private var hotkeySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("全域快捷鍵自訂", systemImage: "keyboard")
                .font(.system(size: 14, weight: .bold))
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("目前生效快捷鍵：")
                        .font(.system(size: 12))
                    Spacer()
                    Text(hotkeyManager.currentDisplayString)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .cornerRadius(6)
                }
                
                Divider()
                
                // Modifiers Selector
                Text("勾選修飾鍵 (Modifiers)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                
                HStack(spacing: 16) {
                    Toggle("⌘ Command", isOn: $hotkeyManager.useCommand)
                    Toggle("⇧ Shift", isOn: $hotkeyManager.useShift)
                    Toggle("⌥ Option", isOn: $hotkeyManager.useOption)
                    Toggle("⌃ Control", isOn: $hotkeyManager.useControl)
                }
                .toggleStyle(CheckboxToggleStyle())
                .font(.system(size: 12))
                
                // Key Selector
                HStack {
                    Text("觸發按鍵 (Key)：")
                        .font(.system(size: 12))
                    
                    Picker("", selection: $hotkeyManager.selectedKeyName) {
                        ForEach(HotkeyManager.availableKeys) { k in
                            Text(k.name).tag(k.name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                    
                    Spacer()
                }
                
                Text("💡 變更後系統會即時熱更新全域快捷鍵，無需重新啟動應用程式。在任何 macOS 全螢幕或背景視窗下均可隨時呼叫快速新增視窗。")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Menu Bar Section
    
    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("macOS 頂端選單列 (Menu Bar)", systemImage: "menubar.rectangle")
                .font(.system(size: 14, weight: .bold))
            
            VStack(alignment: .leading, spacing: 12) {
                Toggle("在 macOS 頂端選單列顯示常駐圖示", isOn: $menuBarController.isEnabled)
                    .font(.system(size: 13, weight: .medium))
                
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("在選單列顯示今日未完成待辦數量角標", isOn: $menuBarController.showBadgeCount)
                        .font(.system(size: 12))
                    
                    Toggle("在選單列圖示旁顯示文字標籤（TaskColumn）", isOn: $menuBarController.showTextLabel)
                        .font(.system(size: 12))
                }
                .disabled(!menuBarController.isEnabled)
                .padding(.leading, 20)
                
                Divider()
                
                HStack {
                    Button(action: {
                        menuBarController.resetStatusItemPosition()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.counterclockwise")
                            Text("重設圖示位置（置於最右側）")
                        }
                    }
                    .controlSize(.small)
                    .disabled(!menuBarController.isEnabled)
                    
                    Spacer()
                }
                .padding(.leading, 20)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("💡 選單列使用指南與排錯說明：")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.85))
                    
                    Text("• 不需要將應用程式搬移至「應用程式 (/Applications)」資料夾，於任何路徑執行選單列功能皆完全正常。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("• 螢幕劉海 (Notch) 遮蔽：在配備劉海的 MacBook 上，若開啟的選單列圖示過多，macOS 會將多出的圖示隱藏在劉海左側。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("• 自訂位置技巧：您可以按住鍵盤上的 ⌘ (Command) 鍵，並用滑鼠拖曳頂部選單列上的圖示，自由移動其左右排列順序（建議拖至靠近控制中心或時間處）。")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(10)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(6)
            }
            .padding(12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(8)
        }
    }
}
