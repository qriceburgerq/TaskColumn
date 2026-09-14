import SwiftUI
import AppKit
import Combine

@MainActor
public class MenuBarController: NSObject, ObservableObject {
    public static let shared = MenuBarController()
    
    @Published public var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "show_in_menu_bar")
            applyMenuBarVisibility()
        }
    }
    
    @Published public var showBadgeCount: Bool {
        didSet {
            UserDefaults.standard.set(showBadgeCount, forKey: "menu_bar_show_badge")
            updateBadge()
        }
    }
    
    @Published public var showTextLabel: Bool {
        didSet {
            UserDefaults.standard.set(showTextLabel, forKey: "menu_bar_show_text")
            updateBadge()
        }
    }
    
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellables = Set<AnyCancellable>()
    
    private override init() {
        if UserDefaults.standard.object(forKey: "show_in_menu_bar") != nil {
            self.isEnabled = UserDefaults.standard.bool(forKey: "show_in_menu_bar")
        } else {
            self.isEnabled = true
        }
        
        if UserDefaults.standard.object(forKey: "menu_bar_show_badge") != nil {
            self.showBadgeCount = UserDefaults.standard.bool(forKey: "menu_bar_show_badge")
        } else {
            self.showBadgeCount = true
        }
        
        if UserDefaults.standard.object(forKey: "menu_bar_show_text") != nil {
            self.showTextLabel = UserDefaults.standard.bool(forKey: "menu_bar_show_text")
        } else {
            self.showTextLabel = false
        }
        
        super.init()
    }
    
    @MainActor
    public func setupMenuBar() {
        // Subscribe to DataManager changes to update badge count
        DataManager.shared.$allTasks
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateBadge()
            }
            .store(in: &cancellables)
        
        applyMenuBarVisibility()
    }
    
    @MainActor
    public func applyMenuBarVisibility() {
        if isEnabled {
            if statusItem == nil {
                createStatusItem()
            }
            updateBadge()
        } else {
            removeStatusItem()
        }
    }
    
    @MainActor
    public func resetStatusItemPosition() {
        // Clear cached positions in UserDefaults that might place it behind the notch
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position Item-0")
        UserDefaults.standard.removeObject(forKey: "NSStatusItem Preferred Position TaskColumnStatusItem")
        
        removeStatusItem()
        isEnabled = true
        createStatusItem()
        updateBadge()
    }
    
    @MainActor
    private func createStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem?.autosaveName = "TaskColumnStatusItem"
        statusItem?.behavior = [.removalAllowed]
        guard let button = statusItem?.button else { return }
        
        button.toolTip = "TaskColumn 待辦事項 (點擊展開)"
        
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let img = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "TaskColumn")?.withSymbolConfiguration(config) {
            img.isTemplate = true
            img.size = NSSize(width: 16, height: 16)
            button.image = img
        } else if let fallback = NSImage(systemSymbolName: "checklist", accessibilityDescription: "TaskColumn") {
            fallback.isTemplate = true
            fallback.size = NSSize(width: 16, height: 16)
            button.image = fallback
        }
        
        button.imagePosition = .imageLeading
        button.action = #selector(statusBarButtonClicked(_:))
        button.target = self
        
        let p = NSPopover()
        p.contentSize = NSSize(width: 350, height: 440)
        p.behavior = .transient
        p.animates = true
        p.contentViewController = NSHostingController(rootView: MenuBarPopoverView(onClose: { [weak self] in
            self?.closePopover()
        }))
        self.popover = p
        
        updateBadge()
    }
    
    @MainActor
    private func removeStatusItem() {
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
        popover = nil
    }
    
    @MainActor
    public func updateBadge() {
        guard let button = statusItem?.button else { return }
        let count = DataManager.shared.todayPendingCount
        var titleParts: [String] = []
        
        if showTextLabel {
            titleParts.append("TaskColumn")
        }
        
        if showBadgeCount && count > 0 {
            titleParts.append("(\(count))")
        }
        
        if titleParts.isEmpty {
            button.title = ""
        } else {
            button.title = " " + titleParts.joined(separator: " ")
        }
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        guard let popover = popover else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    
    @MainActor
    public func closePopover() {
        popover?.performClose(nil)
    }
}

public struct MenuBarPopoverView: View {
    var onClose: () -> Void
    @ObservedObject private var dataManager = DataManager.shared
    @ObservedObject private var authService = GoogleAuthService.shared
    
    @State private var filterMode: Int = 0 // 0: 今日到期, 1: 全部待辦中
    @State private var inlineNewTask: String = ""
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                    Text("TaskColumn")
                        .font(.system(size: 14, weight: .bold))
                }
                
                Spacer()
                
                // Sync button
                Button(action: {
                    dataManager.syncWithGoogle()
                }) {
                    if dataManager.isSyncing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .help("立即與 Google Tasks 同步")
                
                // Quick Add panel shortcut
                Button(action: {
                    onClose()
                    QuickAddPanelController.shared.show()
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(PlainButtonStyle())
                .help("呼叫全螢幕快速新增面板 (Cmd+Shift+A)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            
            // Inline Quick Add TextField directly in menu bar popover!
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                
                TextField("快速新增待辦事項... (按 Enter 送出)", text: $inlineNewTask)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12))
                    .onSubmit {
                        submitInlineTask()
                    }
                
                if !inlineNewTask.isEmpty {
                    Button(action: submitInlineTask) {
                        Image(systemName: "return")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // View Switcher (Segmented: 今日待辦 / 全部待辦)
            Picker("", selection: $filterMode) {
                Text("今日到期 (\(dataManager.todayPendingCount))").tag(0)
                Text("全部待辦 (\(dataManager.allPendingTasks.count))").tag(1)
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            
            Divider()
            
            // Task List
            let displayTasks = filterMode == 0 ? dataManager.todayPendingTasks : dataManager.allPendingTasks
            
            if displayTasks.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                    Text(filterMode == 0 ? "太棒了！今日無未完成待辦" : "太棒了！目前無任何待辦事項")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(filterMode == 0 ? "所有今日事項均已處理完畢。" : "您已完成所有待辦，享受美好的一天吧！")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 30)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(displayTasks) { task in
                            MenuBarTaskRow(task: task)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            Divider()
            
            // Footer Controls
            HStack(spacing: 12) {
                Button(action: {
                    onClose()
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where window.canBecomeKey && window.isVisible {
                        window.makeKeyAndOrderFront(nil)
                        return
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "macwindow")
                        Text("開啟主視窗")
                    }
                    .font(.system(size: 12))
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button("結束") {
                    NSApplication.shared.terminate(nil)
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        }
        .frame(width: 350, height: 440)
    }
    
    private func submitInlineTask() {
        let trimmed = inlineNewTask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        let due: Date? = (filterMode == 0) ? Date() : nil
        _ = dataManager.addTask(title: trimmed, due: due)
        inlineNewTask = ""
    }
}

struct MenuBarTaskRow: View {
    let task: TaskItem
    @ObservedObject private var dataManager = DataManager.shared
    
    var body: some View {
        HStack(spacing: 10) {
            Button(action: {
                dataManager.toggleTaskCompletion(taskId: task.id)
            }) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(task.isCompleted ? .secondary : .accentColor)
            }
            .buttonStyle(PlainButtonStyle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                
                if let due = task.due {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 9))
                        Text(formatDue(due))
                            .font(.system(size: 10))
                    }
                    .foregroundColor(task.isOverdue ? .red : .orange)
                }
            }
            
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .background(Color.primary.opacity(0.02))
    }
    
    private func formatDue(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInYesterday(date) { return "昨天 (已逾期)" }
        if cal.isDateInTomorrow(date) { return "明天" }
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
}
