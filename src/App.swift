import SwiftUI
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup Menu Bar Item
        MenuBarController.shared.setupMenuBar()
        
        // Setup Global Hotkey
        HotkeyManager.shared.onHotKeyTriggered = {
            QuickAddPanelController.shared.toggle()
        }
        HotkeyManager.shared.reRegister()
        
        // Auto sync if user already authenticated
        if GoogleAuthService.shared.isAuthenticated {
            DataManager.shared.syncWithGoogle()
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep running in menu bar even if main window is closed
        return false
    }
}

@main
struct TaskColumnApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var dataManager = DataManager.shared
    
    init() {
        MenuBarController.shared.setupMenuBar()
    }
    
    var body: some Scene {
        WindowGroup {
            MainSplitView()
                .frame(minWidth: 880, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("快速新增待辦事項") {
                    QuickAddPanelController.shared.show()
                }
                .keyboardShortcut("n", modifiers: .command)
            }
            
            CommandMenu("任務") {
                Button("與 Google Tasks 同步") {
                    dataManager.syncWithGoogle()
                }
                .keyboardShortcut("r", modifiers: .command)
                
                Divider()
                
                Button("切換完成狀態") {
                    if let sel = dataManager.selectedTaskId {
                        dataManager.toggleTaskCompletion(taskId: sel)
                    }
                }
                .keyboardShortcut(.space, modifiers: [])
            }
            
            CommandMenu("檢視") {
                Button("放大字體") {
                    dataManager.zoomIn()
                }
                .keyboardShortcut("+", modifiers: .command)
                
                Button("縮小字體") {
                    dataManager.zoomOut()
                }
                .keyboardShortcut("-", modifiers: .command)
                
                Button("實際大小 (100%)") {
                    dataManager.resetZoom()
                }
                .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
