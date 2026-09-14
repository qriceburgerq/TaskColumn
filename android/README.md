# TaskColumn Android Companion App

TaskColumn Android 專屬伴侶應用程式，使用 **Kotlin + Jetpack Compose + Material 3** 開發，與 macOS 桌面版 TaskColumn 共享相同資料模型，並透過 **Google Tasks 雲端伺服器** 實現即時雙向同步！

---

## 🌟 核心功能

1. **雙向無縫同步**：登入 Google 帳號後，直接與 Google Tasks 雙向同步（在 Mac 新增的任務手機即刻出現，手機打勾 Mac 同步完成）。
2. **智慧視角抽屜**：支援「待辦中」、「今天到期」、「即將到來」、「全部待辦」、「已完成事項」、「垃圾桶」與自訂清單。
3. **單手極速新增**：懸浮按鈕（FAB）一鍵叫出底部輸入面板，支援「今天」、「明天」到期日快捷設定。
4. **Notion 風格全頁備忘**：點擊任何任務即可展開全頁備忘筆記撰寫、支援 Material 3 原生日曆選取器（DatePicker）。
5. **垃圾桶與防呆還原**：刪除的任務在本機安全保留，可隨時手動還原。

---

## 🚀 GitHub Actions 雲端自動打包與安裝

本專案已配置完整的 CI/CD 自動建置流水線（`.github/workflows/build-android-apk.yml`）：

### 步驟 1：推送到您的 GitHub 倉庫
若您尚未關聯遠端 GitHub 倉庫，請在專案根目錄執行：
```bash
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/YOUR_REPO_NAME.git
git branch -M main
git push -u origin main
```

### 步驟 2：雲端自動編譯產出 APK
1. 程式碼推送至 GitHub 後，切換至 GitHub 倉庫頁面的 **Actions** 分頁。
2. 您會看到正在運行的 **Build Android APK** 工作流程（約需 2~3 分鐘）。
3. 建置成功後，點進該次 Workflow，最下方的 **Artifacts** 區塊即可直接下載 **`TaskColumn-Android-Debug-APK`**！

### 步驟 3：安裝至 Android 手機
將下載的 `app-debug.apk` 透過 LINE、USB、Telegram 或 Google Drive 傳至手機，點擊即可完成安裝！

---

## 🔑 Google Cloud 控制台 Android 憑證配置

為了讓手機端順利連線 Google Tasks，建議在現有的 Google Cloud 專案中新增 Android 用戶端：
1. 開啟 [Google Cloud Console](https://console.cloud.google.com/) -> 進入您的 TaskColumn 專案。
2. 進入 **API 和服務** -> **憑證** -> 點擊 **建立憑證** -> 選擇 **OAuth 用戶端 ID**。
3. 應用程式類型選擇 **Android**：
   - **套件名稱 (Package name)**：`com.antigravity.taskcolumn`
   - **SHA-1 簽署憑證指紋**：
     Debug 預設簽章可使用標準金鑰庫生成：
     ```bash
     keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
     ```
4. 儲存即可！手機端即可一鍵喚起授權視窗。
