import SwiftUI

public struct TaskDetailView: View {
    public let taskId: String
    public var isFullPageFocus: Bool = false
    public var onToggleFocus: (() -> Void)? = nil
    public var onExitFocus: (() -> Void)? = nil
    
    @ObservedObject private var dataManager = DataManager.shared
    
    public init(
        taskId: String,
        isFullPageFocus: Bool = false,
        onToggleFocus: (() -> Void)? = nil,
        onExitFocus: (() -> Void)? = nil
    ) {
        self.taskId = taskId
        self.isFullPageFocus = isFullPageFocus
        self.onToggleFocus = onToggleFocus
        self.onExitFocus = onExitFocus
    }
    
    @ViewBuilder
    public var body: some View {
        if let task = dataManager.allTasks.first(where: { $0.id == taskId }) ?? dataManager.trashTasks.first(where: { $0.id == taskId }) {
            TaskDetailContentView(
                task: task,
                isFullPageFocus: isFullPageFocus,
                onToggleFocus: onToggleFocus,
                onExitFocus: onExitFocus
            )
            .id(task.id) // Reset local view state when switching tasks
        } else {
            VStack(spacing: 12) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.appScale(38))
                    .foregroundColor(.secondary.opacity(0.4))
                Text("選取待辦事項以檢視詳細資料與備忘")
                    .font(.appScale(14))
                    .foregroundColor(.secondary)
                
                if isFullPageFocus {
                    Button("返回三直欄檢視 (Esc)") {
                        onExitFocus?()
                    }
                    .font(.appScale(12))
                    .buttonStyle(BorderedButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
        }
    }
}

struct TaskDetailContentView: View {
    let task: TaskItem
    var isFullPageFocus: Bool
    var onToggleFocus: (() -> Void)?
    var onExitFocus: (() -> Void)?
    
    @ObservedObject private var dataManager = DataManager.shared
    
    @State private var title: String
    @State private var notes: String
    @State private var selectedListId: String
    @State private var dueDate: Date
    @State private var hasDueDate: Bool
    @State private var newSubtaskTitle: String = ""
    
    init(
        task: TaskItem,
        isFullPageFocus: Bool = false,
        onToggleFocus: (() -> Void)? = nil,
        onExitFocus: (() -> Void)? = nil
    ) {
        self.task = task
        self.isFullPageFocus = isFullPageFocus
        self.onToggleFocus = onToggleFocus
        self.onExitFocus = onExitFocus
        
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes ?? "")
        _selectedListId = State(initialValue: task.listId)
        _dueDate = State(initialValue: task.due ?? Date())
        _hasDueDate = State(initialValue: task.due != nil)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            if isFullPageFocus {
                focusTopNavBar
            } else {
                sidebarTopNavBar
            }
            
            // Trash Notice Banner
            if task.isDeleted {
                HStack(spacing: 8) {
                    Image(systemName: "trash.fill")
                        .font(.appScale(12))
                        .foregroundColor(.orange)
                    Text("此待辦事項位於垃圾桶中，30 天後將自動永久清除")
                        .font(.appScale(11))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("還原") {
                        dataManager.restoreTask(taskId: task.id)
                    }
                    .font(.appScale(11))
                    .buttonStyle(BorderedProminentButtonStyle())
                    .controlSize(.small)
                    
                    Button("永久刪除") {
                        dataManager.permanentDeleteTask(taskId: task.id)
                    }
                    .font(.appScale(11))
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
                    .foregroundColor(.red)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
                
                Divider()
            }
            
            // Document Content
            ScrollView {
                if isFullPageFocus {
                    // Centered Notion Document Canvas
                    HStack(spacing: 0) {
                        Spacer()
                        VStack(alignment: .leading, spacing: 20) {
                            titleSection
                            propertiesSection
                            subtasksSection
                            Divider()
                            notesSection
                        }
                        .frame(maxWidth: 820)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 28)
                        Spacer()
                    }
                } else {
                    // Standard 3rd Column Layout
                    VStack(alignment: .leading, spacing: 18) {
                        titleSection
                        propertiesSection
                        subtasksSection
                        Divider()
                        notesSection
                    }
                    .padding(18)
                }
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Navigation Bars
    
    private var sidebarTopNavBar: some View {
        HStack(spacing: 10) {
            if task.isDeleted {
                Button(action: {
                    dataManager.restoreTask(taskId: task.id)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward.circle.fill")
                        Text("還原事項")
                    }
                    .font(.appScale(12, weight: .medium))
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    dataManager.permanentDeleteTask(taskId: task.id)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "xmark.circle")
                        Text("永久刪除")
                    }
                    .font(.appScale(12))
                    .foregroundColor(.red)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                Button(action: {
                    dataManager.toggleTaskCompletion(taskId: task.id)
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.appScale(15))
                        Text(task.isCompleted ? "已完成" : "標記為完成")
                            .font(.appScale(12, weight: .medium))
                    }
                    .foregroundColor(task.isCompleted ? .secondary : .accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(task.isCompleted ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.12))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Spacer()
            
            // Notion-like Expand Button
            Button(action: {
                onToggleFocus?()
            }) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.appScale(12))
                    .foregroundColor(.secondary)
                    .padding(5)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(5)
            }
            .buttonStyle(PlainButtonStyle())
            .help("放大至全視窗專注撰寫備忘 (⌘⌥F)")
            
            if !task.isDeleted {
                Button(action: {
                    dataManager.deleteTask(taskId: task.id)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red.opacity(0.8))
                        .font(.appScale(13))
                        .padding(5)
                        .background(Color.red.opacity(0.08))
                        .cornerRadius(5)
                }
                .buttonStyle(PlainButtonStyle())
                .help("將此事項移入垃圾桶")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
    
    private var focusTopNavBar: some View {
        HStack(spacing: 12) {
            Button(action: {
                onExitFocus?()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.left")
                        .font(.appScale(12, weight: .bold))
                    Text("返回三直欄清單 (Esc)")
                        .font(.appScale(12, weight: .medium))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .keyboardShortcut(.cancelAction)
            
            // Breadcrumb
            let listTitle = dataManager.lists.first(where: { $0.id == selectedListId })?.title ?? "待辦清單"
            HStack(spacing: 4) {
                Image(systemName: "folder")
                    .font(.appScale(11))
                    .foregroundColor(.secondary)
                Text(listTitle)
                    .font(.appScale(11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Status Checkbox
            Button(action: {
                dataManager.toggleTaskCompletion(taskId: task.id)
            }) {
                HStack(spacing: 6) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.appScale(14))
                    Text(task.isCompleted ? "已完成" : "進行中")
                        .font(.appScale(12, weight: .medium))
                }
                .foregroundColor(task.isCompleted ? .secondary : .accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(task.isCompleted ? Color.secondary.opacity(0.12) : Color.accentColor.opacity(0.12))
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Delete button
            Button(action: {
                dataManager.deleteTask(taskId: task.id)
                onExitFocus?()
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.8))
                    .font(.appScale(13))
            }
            .buttonStyle(PlainButtonStyle())
            .help("刪除此待辦事項")
            
            // Restore button
            Button(action: {
                onExitFocus?()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                    Text("還原三欄")
                }
                .font(.appScale(11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.15))
                .foregroundColor(.accentColor)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .help("還原為三直欄視角 (⌘⌥F)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
    }
    
    // MARK: - Sections
    
    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isFullPageFocus {
                TextField("輸入待辦標題...", text: $title)
                    .font(.appScale(24, weight: .bold))
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.vertical, 4)
                    .onChange(of: title) {
                        saveChanges()
                    }
            } else {
                TextField("待辦標題", text: $title)
                    .font(.appScale(17, weight: .bold))
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .onChange(of: title) {
                        saveChanges()
                    }
            }
        }
    }
    
    private var propertiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Belonging List Picker
            HStack(alignment: .center, spacing: 8) {
                Label("所屬分類", systemImage: "folder")
                    .font(.appScale(12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                
                Picker("", selection: $selectedListId) {
                    ForEach(dataManager.lists) { l in
                        Text(l.title).tag(l.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
                .onChange(of: selectedListId) {
                    dataManager.moveTask(taskId: task.id, toListId: selectedListId)
                }
                
                Spacer()
            }
            
            // Due Date Row
            HStack(alignment: .center, spacing: 8) {
                Label("到期日", systemImage: "calendar")
                    .font(.appScale(12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                
                HStack(spacing: 6) {
                    Button("今天") { applyDate(Date()) }
                        .buttonStyle(BorderedButtonStyle())
                        .controlSize(.small)
                        .font(.appScale(11))
                    
                    Button("明天") {
                        if let tm = Calendar.current.date(byAdding: .day, value: 1, to: Date()) {
                            applyDate(tm)
                        }
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
                    .font(.appScale(11))
                    
                    Button("下週") {
                        if let nw = Calendar.current.date(byAdding: .day, value: 7, to: Date()) {
                            applyDate(nw)
                        }
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
                    .font(.appScale(11))
                    
                    // Direct Custom Date Picker (Always accessible for any custom date)
                    DatePicker("", selection: $dueDate, displayedComponents: [.date])
                        .datePickerStyle(CompactDatePickerStyle())
                        .labelsHidden()
                        .onChange(of: dueDate) {
                            applyDate(dueDate)
                        }
                    
                    if hasDueDate {
                        Button("清除") {
                            hasDueDate = false
                            var updated = task
                            updated.due = nil
                            dataManager.updateTask(updated)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.red)
                        .font(.appScale(11))
                        .padding(.leading, 2)
                    }
                }
                
                Spacer()
            }
        }
        .padding(isFullPageFocus ? 12 : 10)
        .background(Color(NSColor.controlBackgroundColor).opacity(isFullPageFocus ? 0.5 : 0.4))
        .cornerRadius(8)
    }
    
    private var subtasksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("階層子任務", systemImage: "list.bullet.indent")
                    .font(.appScale(12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                let completedCount = task.subtasks.filter { $0.isCompleted }.count
                if !task.subtasks.isEmpty {
                    Text("\(completedCount)/\(task.subtasks.count) 完成")
                        .font(.appScale(11))
                        .foregroundColor(.secondary)
                }
            }
            
            ForEach(task.subtasks) { sub in
                HStack(spacing: 8) {
                    Button(action: {
                        dataManager.toggleTaskCompletion(taskId: sub.id)
                    }) {
                        Image(systemName: sub.isCompleted ? "checkmark.square.fill" : "square")
                            .foregroundColor(sub.isCompleted ? .secondary : .accentColor)
                            .font(.appScale(13))
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Text(sub.title)
                        .font(.appScale(13))
                        .strikethrough(sub.isCompleted)
                        .foregroundColor(sub.isCompleted ? .secondary : .primary)
                    
                    Spacer()
                    
                    Button(action: {
                        dataManager.deleteTask(taskId: sub.id)
                    }) {
                        Image(systemName: "xmark")
                            .font(.appScale(10))
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(4)
            }
            
            // Add subtask input
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.appScale(11))
                    .foregroundColor(.secondary)
                
                TextField("新增子任務... (按 Enter 儲存)", text: $newSubtaskTitle)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.appScale(12))
                    .onSubmit {
                        let trimmed = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        dataManager.addSubtask(parentTaskId: task.id, title: trimmed)
                        newSubtaskTitle = ""
                    }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
            .cornerRadius(6)
        }
    }
    
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("詳細資料與備忘筆記", systemImage: "text.alignleft")
                    .font(.appScale(12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if !notes.isEmpty {
                    Text("\(notes.count) 字")
                        .font(.appScale(10))
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
            
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text(isFullPageFocus ? "在此開始撰寫詳細備忘、筆記、Markdown 記錄或行動計畫..." : "新增備忘筆記...")
                        .font(.appScale(isFullPageFocus ? 14 : 13))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                
                TextEditor(text: $notes)
                    .font(.appScale(isFullPageFocus ? 14 : 13))
                    .lineSpacing(isFullPageFocus ? 6 : 4)
                    .frame(minHeight: isFullPageFocus ? 360 : 130)
                    .padding(6)
                    .background(Color(NSColor.controlBackgroundColor).opacity(isFullPageFocus ? 0.3 : 1.0))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                    .onChange(of: notes) {
                        saveChanges()
                    }
            }
        }
    }
    
    private func saveChanges() {
        var updated = task
        updated.title = title
        updated.notes = notes.isEmpty ? nil : notes
        dataManager.updateTask(updated)
    }
    
    private func applyDate(_ date: Date) {
        dueDate = date
        hasDueDate = true
        var updated = task
        updated.due = date
        dataManager.updateTask(updated)
    }
}
