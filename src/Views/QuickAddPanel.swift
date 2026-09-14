import SwiftUI
import AppKit

public class QuickAddPanelController: NSObject {
    public static let shared = QuickAddPanelController()
    
    private var panel: NSPanel?
    
    private override init() {
        super.init()
    }
    
    @MainActor
    public func toggle() {
        if let panel = panel, panel.isVisible {
            hide()
        } else {
            show()
        }
    }
    
    @MainActor
    public func show() {
        if panel == nil {
            createPanel()
        }
        
        guard let panel = panel else { return }
        
        // Re-center on the current mouse screen
        if let screen = NSScreen.main {
            let screenRect = screen.visibleFrame
            let x = screenRect.origin.x + (screenRect.width - 520) / 2
            let y = screenRect.origin.y + (screenRect.height - 280) / 2 + 100
            panel.setFrame(NSRect(x: x, y: y, width: 520, height: 260), display: true)
        }
        
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }
    
    @MainActor
    public func hide() {
        panel?.orderOut(nil)
    }
    
    @MainActor
    private func createPanel() {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 260),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        p.isFloatingPanel = true
        p.level = .floating
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.isMovableByWindowBackground = true
        p.backgroundColor = .clear
        p.hasShadow = true
        
        let contentView = QuickAddView(onClose: { [weak self] in
            self?.hide()
        })
        p.contentView = NSHostingView(rootView: contentView)
        self.panel = p
    }
}

public struct QuickAddView: View {
    var onClose: () -> Void
    
    @ObservedObject private var dataManager = DataManager.shared
    @State private var taskTitle: String = ""
    @State private var taskNotes: String = ""
    @State private var selectedListId: String = ""
    @State private var dueDateOption: DueOption = .none
    @State private var customDate: Date = Date()
    @State private var showNotes: Bool = false
    @FocusState private var isTitleFocused: Bool
    
    enum DueOption: String, CaseIterable, Identifiable {
        case none = "無日期"
        case today = "今天"
        case tomorrow = "明天"
        case weekend = "本週末"
        case custom = "自訂"
        var id: String { rawValue }
    }
    
    public init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                Text("快速新增待辦事項")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("Esc 關閉")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)
            
            Divider()
            
            // Input Body
            VStack(alignment: .leading, spacing: 12) {
                // Title Field
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "circle")
                        .foregroundColor(.secondary)
                    TextField("想要完成什麼任務？ (按 Enter 儲存)", text: $taskTitle)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.system(size: 15))
                        .focused($isTitleFocused)
                        .onSubmit {
                            submitTask()
                        }
                }
                .padding(10)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.8))
                .cornerRadius(8)
                
                // Target List & Due Date Options
                HStack(spacing: 12) {
                    // List selector
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        Picker("", selection: $selectedListId) {
                            ForEach(dataManager.lists) { list in
                                Text(list.title).tag(list.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 150)
                    }
                    
                    Spacer()
                    
                    // Due date quick pickers
                    HStack(spacing: 4) {
                        ForEach(DueOption.allCases) { opt in
                            Button(action: {
                                dueDateOption = opt
                            }) {
                                Text(opt.rawValue)
                                    .font(.system(size: 11, weight: dueDateOption == opt ? .semibold : .regular))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(dueDateOption == opt ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                                    .foregroundColor(dueDateOption == opt ? .accentColor : .primary)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
                
                if dueDateOption == .custom {
                    DatePicker("指定到期日", selection: $customDate, displayedComponents: [.date])
                        .datePickerStyle(CompactDatePickerStyle())
                        .font(.caption)
                }
                
                // Expandable Notes
                if showNotes {
                    TextField("新增詳細備忘或說明...", text: $taskNotes)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .font(.caption)
                }
            }
            .padding(16)
            
            Divider()
            
            // Action Footer
            HStack {
                Button(action: {
                    withAnimation {
                        showNotes.toggle()
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showNotes ? "text.bubble.fill" : "text.bubble")
                        Text(showNotes ? "隱藏備忘" : "加入詳細備忘")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
                
                Button("取消") {
                    onClose()
                }
                .keyboardShortcut(.cancelAction)
                
                Button("建立待辦 (↵)") {
                    submitTask()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
        }
        .frame(width: 520)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            if let firstList = dataManager.lists.first {
                selectedListId = firstList.id
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
        }
    }
    
    private func submitTask() {
        let trimmed = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var due: Date? = nil
        let cal = Calendar.current
        let now = Date()
        
        switch dueDateOption {
        case .none:
            due = nil
        case .today:
            due = now
        case .tomorrow:
            due = cal.date(byAdding: .day, value: 1, to: now)
        case .weekend:
            let weekday = cal.component(.weekday, from: now)
            let daysToAdd = (7 - weekday + 7) % 7
            due = cal.date(byAdding: .day, value: daysToAdd == 0 ? 7 : daysToAdd, to: now)
        case .custom:
            due = customDate
        }
        
        let notesParam = taskNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : taskNotes
        
        _ = dataManager.addTask(
            listId: selectedListId.isEmpty ? nil : selectedListId,
            title: trimmed,
            notes: notesParam,
            due: due
        )
        
        // Reset and close
        taskTitle = ""
        taskNotes = ""
        dueDateOption = .none
        onClose()
    }
}
