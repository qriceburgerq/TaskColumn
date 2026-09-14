import SwiftUI
import UniformTypeIdentifiers

public struct MainSplitView: View {
    @ObservedObject private var dataManager = DataManager.shared
    @ObservedObject private var authService = GoogleAuthService.shared
    
    // Proportional Layout Controls
    @AppStorage("column_sidebar_ratio") private var sidebarRatio: Double = 0.22
    @AppStorage("column_tasklist_ratio") private var taskListRatio: Double = 0.38
    @State private var showSidebar: Bool = true
    @State private var showDetail: Bool = true
    @State private var isMemoFocused: Bool = false
    
    // Dialogs
    @State private var showingAddListAlert = false
    @State private var newListName = ""
    @State private var quickAddInput = ""
    @State private var showingSettings = false
    
    // Dragging active item id
    @State private var draggingFilterId: String? = nil
    @State private var draggingListId: String? = nil
    @State private var draggingTaskId: String? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Global Top Toolbar
            topControlBar
            
            Divider()
            
            // MARK: - Main Columns Content with Adaptive Proportional Resizing
            GeometryReader { geometry in
                let widths = computeColumnWidths(totalWidth: geometry.size.width)
                
                HStack(spacing: 0) {
                    if isMemoFocused {
                        // Notion-Style Full-Window Memo View (occupies entire content area within main window)
                        TaskDetailView(
                            taskId: dataManager.selectedTaskId ?? "",
                            isFullPageFocus: true,
                            onExitFocus: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isMemoFocused = false
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                    } else {
                        // Standard Multi-Column with Adaptive Proportional Resizing & Folding
                        
                        // Column 1: Sidebar (Lists & Smart Views)
                        if showSidebar {
                            sidebarColumn
                                .frame(width: widths.sidebar)
                                .transition(.move(edge: .leading).combined(with: .opacity))
                            
                            // Proportional Divider 1
                            ProportionalDivider { delta in
                                handleSidebarDividerDrag(delta: delta, totalWidth: geometry.size.width)
                            }
                        }
                        
                        // Column 2: Tasks List or Month Calendar
                        Group {
                            if dataManager.selectedFilter == .calendar {
                                CalendarMonthView(onSelectTask: { taskId in
                                    dataManager.selectedTaskId = taskId
                                })
                            } else {
                                taskListColumn
                            }
                        }
                        .frame(width: showDetail ? widths.taskList : nil)
                        .frame(maxWidth: showDetail ? nil : .infinity)
                        
                        // Proportional Divider 2
                        if showDetail {
                            ProportionalDivider { delta in
                                handleTaskListDividerDrag(delta: delta, totalWidth: geometry.size.width)
                            }
                            
                            // Column 3: Task Details & Subtasks
                            TaskDetailView(
                                taskId: dataManager.selectedTaskId ?? "",
                                isFullPageFocus: false,
                                onToggleFocus: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        ensureTaskSelected()
                                        isMemoFocused = true
                                    }
                                }
                            )
                            .frame(minWidth: widths.detail, maxWidth: .infinity)
                            .background(Color(NSColor.windowBackgroundColor))
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingAddListAlert) {
            addListSheet
        }
        .onAppear {
            MenuBarController.shared.setupMenuBar()
        }
    }
    
    // MARK: - Adaptive Proportional Layout Engine
    
    private func computeColumnWidths(totalWidth: CGFloat) -> (sidebar: CGFloat, taskList: CGFloat, detail: CGFloat) {
        let minSidebar: CGFloat = 180
        let maxSidebar: CGFloat = 360
        let minTaskList: CGFloat = (dataManager.selectedFilter == .calendar) ? 420 : 260
        let minDetail: CGFloat = 300
        
        let dividerWidth: CGFloat = 5
        let numDividers: CGFloat = (showSidebar ? 1 : 0) + (showDetail ? 1 : 0)
        let availableWidth = max(100, totalWidth - (numDividers * dividerWidth))
        
        if showSidebar && showDetail {
            // Three columns active: allocate proportionally based on ratios
            var sRatio = CGFloat(sidebarRatio)
            var tRatio = CGFloat(taskListRatio)
            
            if sRatio + tRatio > 0.75 {
                let factor = 0.75 / (sRatio + tRatio)
                sRatio *= factor
                tRatio *= factor
            }
            let dRatio = max(0.20, 1.0 - sRatio - tRatio)
            let totalRatio = sRatio + tRatio + dRatio
            
            var wSidebar = availableWidth * (sRatio / totalRatio)
            var wTaskList = availableWidth * (tRatio / totalRatio)
            
            wSidebar = min(max(wSidebar, minSidebar), maxSidebar)
            wTaskList = max(wTaskList, minTaskList)
            
            var wDetail = availableWidth - wSidebar - wTaskList
            if wDetail < minDetail {
                let deficit = minDetail - wDetail
                wDetail = minDetail
                let takeFromTask = min(deficit, max(0, wTaskList - minTaskList))
                wTaskList -= takeFromTask
                let remainingDeficit = deficit - takeFromTask
                wSidebar = max(minSidebar, wSidebar - remainingDeficit)
            }
            
            return (wSidebar, wTaskList, max(minDetail, wDetail))
        } else if showSidebar && !showDetail {
            let sRatio = CGFloat(sidebarRatio)
            let tRatio = CGFloat(taskListRatio)
            let normS = sRatio / max(0.1, sRatio + tRatio)
            var wSidebar = availableWidth * normS
            wSidebar = min(max(wSidebar, minSidebar), maxSidebar)
            let wTaskList = max(minTaskList, availableWidth - wSidebar)
            return (wSidebar, wTaskList, 0)
        } else if !showSidebar && showDetail {
            let tRatio = CGFloat(taskListRatio)
            let dRatio = max(0.20, 1.0 - CGFloat(sidebarRatio) - tRatio)
            let normT = tRatio / max(0.1, tRatio + dRatio)
            var wTaskList = availableWidth * normT
            wTaskList = max(wTaskList, minTaskList)
            var wDetail = availableWidth - wTaskList
            if wDetail < minDetail {
                wDetail = minDetail
                wTaskList = max(minTaskList, availableWidth - minDetail)
            }
            return (0, wTaskList, wDetail)
        } else {
            return (0, availableWidth, 0)
        }
    }
    
    private func handleSidebarDividerDrag(delta: CGFloat, totalWidth: CGFloat) {
        let dividerWidth: CGFloat = 5
        let numDividers: CGFloat = (showSidebar ? 1 : 0) + (showDetail ? 1 : 0)
        let availableWidth = max(1, totalWidth - (numDividers * dividerWidth))
        let currentWidths = computeColumnWidths(totalWidth: totalWidth)
        
        let newSidebarWidth = min(max(currentWidths.sidebar + delta, 180), 380)
        let newRatio = Double(newSidebarWidth / availableWidth)
        sidebarRatio = min(max(newRatio, 0.15), 0.35)
    }
    
    private func handleTaskListDividerDrag(delta: CGFloat, totalWidth: CGFloat) {
        let dividerWidth: CGFloat = 5
        let numDividers: CGFloat = (showSidebar ? 1 : 0) + (showDetail ? 1 : 0)
        let availableWidth = max(1, totalWidth - (numDividers * dividerWidth))
        let currentWidths = computeColumnWidths(totalWidth: totalWidth)
        
        let minTaskList: CGFloat = (dataManager.selectedFilter == .calendar) ? 420 : 260
        let maxTaskList = availableWidth - currentWidths.sidebar - 300
        let newTaskListWidth = min(max(currentWidths.taskList + delta, minTaskList), max(minTaskList, maxTaskList))
        let newRatio = Double(newTaskListWidth / availableWidth)
        taskListRatio = min(max(newRatio, 0.25), 0.55)
    }
    
    private func ensureTaskSelected() {
        if dataManager.selectedTaskId == nil {
            if let first = dataManager.currentFilteredTasks.first {
                dataManager.selectedTaskId = first.id
            }
        }
    }
    
    // MARK: - Top Control Bar (Fold, Notion Focus Memo, Settings)
    
    private var topControlBar: some View {
        HStack(spacing: 12) {
            // Sidebar Toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isMemoFocused { isMemoFocused = false }
                    showSidebar.toggle()
                }
            }) {
                Image(systemName: showSidebar ? "sidebar.leading" : "sidebar.left")
                    .font(.appScale(13))
                    .foregroundColor(showSidebar ? .accentColor : .secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help(showSidebar ? "折疊左側清單欄 (⌘⌥S)" : "展開左側清單欄 (⌘⌥S)")
            .keyboardShortcut("s", modifiers: [.command, .option])
            
            // App Name & Status
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.appScale(14, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("TaskColumn")
                    .font(.appScale(13, weight: .bold))
            }
            
            Spacer()
            
            if !isMemoFocused {
                // Detail Toggle
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showDetail.toggle()
                    }
                }) {
                    Image(systemName: showDetail ? "sidebar.trailing" : "sidebar.right")
                        .font(.appScale(13))
                        .foregroundColor(showDetail ? .accentColor : .secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .help(showDetail ? "折疊右側詳細欄 (⌘⌥D)" : "展開右側詳細欄 (⌘⌥D)")
                .keyboardShortcut("d", modifiers: [.command, .option])
            }
            
            // Settings Button
            Button(action: { showingSettings = true }) {
                Image(systemName: "gearshape")
                    .font(.appScale(13))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(PlainButtonStyle())
            .help("偏好設定 (Google 登入、字體縮放、快捷鍵自訂)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }
    
    // MARK: - Column 1: Sidebar
    
    private var sidebarColumn: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    // Smart Filters Section
                    Text("智慧視角")
                        .font(.appScale(11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                    
                    ForEach(dataManager.smartFilters) { filter in
                        SmartFilterRow(
                            type: filter,
                            count: dataManager.count(for: filter),
                            iconColor: filterIconColor(filter),
                            isSelected: dataManager.selectedFilter == filter
                        ) {
                            dataManager.selectedFilter = filter
                        }
                        .contextMenu {
                            if filter == .completed {
                                Button(role: .destructive) {
                                    dataManager.trashAllCompletedTasks()
                                } label: {
                                    Label("將所有已完成事項移入垃圾桶", systemImage: "trash")
                                }
                                .disabled(dataManager.count(for: .completed) == 0)
                            } else if filter == .trash {
                                Button(role: .destructive) {
                                    dataManager.emptyTrash()
                                } label: {
                                    Label("清空垃圾桶", systemImage: "trash.slash")
                                }
                                .disabled(dataManager.trashTasks.isEmpty)
                            }
                        }
                        .onDrag {
                            self.draggingFilterId = filter.id
                            return NSItemProvider(object: filter.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: SmartFilterDropDelegate(targetItem: filter, dataManager: dataManager, draggingId: $draggingFilterId))
                    }
                    
                    // Task Lists Section (Supports Drag and Drop Reordering!)
                    HStack {
                        Text("待辦分類清單")
                            .font(.appScale(11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button(action: {
                            newListName = ""
                            showingAddListAlert = true
                        }) {
                            Image(systemName: "plus")
                                .font(.appScale(11, weight: .bold))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .help("新增分類清單")
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                    
                    ForEach(dataManager.lists) { list in
                        let isSel: Bool = {
                            if case .list(let id) = dataManager.selectedFilter { return id == list.id }
                            return false
                        }()
                        
                        ListRowView(
                            list: list,
                            count: dataManager.count(for: .list(id: list.id)),
                            isSelected: isSel
                        ) {
                            dataManager.selectedFilter = .list(id: list.id)
                        } onDelete: {
                            dataManager.deleteList(id: list.id)
                        }
                        .onDrag {
                            self.draggingListId = list.id
                            return NSItemProvider(object: list.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: ListDropDelegate(targetItem: list, dataManager: dataManager, draggingId: $draggingListId))
                    }
                }
                .padding(.horizontal, 6)
            }
            
            Divider()
            
            // Bottom Google Account & Sync Status
            HStack(spacing: 8) {
                Circle()
                    .fill(authService.isAuthenticated ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                
                Text(authService.isAuthenticated ? (authService.userEmail ?? "Google 帳號已連線") : "本機獨立模式")
                    .font(.appScale(11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Button(action: {
                    dataManager.syncWithGoogle()
                }) {
                    if dataManager.isSyncing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.appScale(12))
                            .foregroundColor(.secondary)
                    }
                }
                .buttonStyle(PlainButtonStyle())
                .help("與 Google Tasks 同步 (⌘ R)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        }
        .background(Color(NSColor.windowBackgroundColor).opacity(0.7))
    }
    
    // MARK: - Column 2: Tasks List Column
    
    private var taskListColumn: some View {
        VStack(spacing: 0) {
            // Header: Current Filter Title + Sort Options
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(currentFilterTitle)
                        .font(.appScale(17, weight: .bold))
                    
                    let count = dataManager.currentFilteredTasks.count
                    Text("\(count) 項待辦")
                        .font(.appScale(11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if case .trash = dataManager.selectedFilter {
                    if !dataManager.trashTasks.isEmpty {
                        Button("清空垃圾桶") {
                            dataManager.emptyTrash()
                        }
                        .font(.appScale(11))
                        .buttonStyle(BorderedButtonStyle())
                        .controlSize(.small)
                        .foregroundColor(.red)
                    }
                } else if case .completed = dataManager.selectedFilter {
                    HStack(spacing: 8) {
                        if dataManager.count(for: .completed) > 0 {
                            Button("移入垃圾桶") {
                                dataManager.trashAllCompletedTasks()
                            }
                            .font(.appScale(11))
                            .buttonStyle(BorderedButtonStyle())
                            .controlSize(.small)
                            .foregroundColor(.red)
                            .help("將所有已完成待辦移入垃圾桶")
                        }
                        
                        Menu {
                            ForEach(TaskSortOrder.allCases) { order in
                                Button(action: {
                                    dataManager.sortOrder = order
                                }) {
                                    HStack {
                                        Text(order.rawValue)
                                        if dataManager.sortOrder == order {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.up.arrow.down")
                                Text(dataManager.sortOrder.rawValue)
                            }
                            .font(.appScale(11))
                        }
                        .menuStyle(BorderlessButtonMenuStyle())
                        .frame(width: 120)
                    }
                } else {
                    Menu {
                        ForEach(TaskSortOrder.allCases) { order in
                            Button(action: {
                                dataManager.sortOrder = order
                            }) {
                                HStack {
                                    Text(order.rawValue)
                                    if dataManager.sortOrder == order {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.arrow.down")
                            Text(dataManager.sortOrder.rawValue)
                        }
                        .font(.appScale(11))
                    }
                    .menuStyle(BorderlessButtonMenuStyle())
                    .frame(width: 120)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)
            
            // Search Field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.appScale(12))
                TextField("搜尋待辦或備忘關鍵字...", text: $dataManager.searchQuery)
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.appScale(12))
                
                if !dataManager.searchQuery.isEmpty {
                    Button(action: { dataManager.searchQuery = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.appScale(12))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
            
            // Quick Add or Trash Banner
            if case .trash = dataManager.selectedFilter {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundColor(.secondary)
                        .font(.appScale(11))
                    Text("移至垃圾桶的事項保留 30 天後自動永久清除。")
                        .font(.appScale(11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(6)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.accentColor)
                    TextField("+ 在此清單新增待辦... (按 Enter)", text: $quickAddInput)
                        .textFieldStyle(PlainTextFieldStyle())
                        .font(.appScale(13))
                        .onSubmit {
                            submitInlineTask()
                        }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .cornerRadius(6)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
            }
            
            Divider()
            
            // Task Items List (Supports Drag & Drop Reordering in Manual Mode)
            let filtered = dataManager.currentFilteredTasks
            
            if filtered.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: dataManager.selectedFilter == .trash ? "trash" : "tray")
                        .font(.appScale(32))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(dataManager.selectedFilter == .trash ? "垃圾桶目前是空的" : "此清單無待辦事項")
                        .font(.appScale(13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(
                    get: { dataManager.selectedTaskId },
                    set: { dataManager.selectedTaskId = $0 }
                )) {
                    if case .trash = dataManager.selectedFilter {
                        ForEach(filtered) { task in
                            TrashTaskRowView(task: task, isSelected: dataManager.selectedTaskId == task.id)
                                .tag(task.id)
                                .onTapGesture {
                                    dataManager.selectedTaskId = task.id
                                }
                        }
                    } else {
                        ForEach(filtered) { task in
                            TaskRowView(task: task, isSelected: dataManager.selectedTaskId == task.id)
                                .tag(task.id)
                                .onTapGesture {
                                    dataManager.selectedTaskId = task.id
                                }
                                .onDrag {
                                    self.draggingTaskId = task.id
                                    return NSItemProvider(object: task.id as NSString)
                                }
                                .onDrop(of: [.text], delegate: TaskDropDelegate(targetItem: task, dataManager: dataManager, draggingId: $draggingTaskId))
                                .contextMenu {
                                    Button(task.isCompleted ? "標記為未完成" : "標記為已完成") {
                                        dataManager.toggleTaskCompletion(taskId: task.id)
                                    }
                                    
                                    Menu("移動到清單") {
                                        ForEach(dataManager.lists) { l in
                                            Button(l.title) {
                                                dataManager.moveTask(taskId: task.id, toListId: l.id)
                                            }
                                        }
                                    }
                                    
                                    Divider()
                                    
                                    Button(role: .destructive) {
                                        dataManager.deleteTask(taskId: task.id)
                                    } label: {
                                        Text(task.isCompleted ? "將此已完成事項移入垃圾桶" : "移入垃圾桶")
                                    }
                                    
                                    if task.isCompleted {
                                        Button(role: .destructive) {
                                            dataManager.trashAllCompletedTasks()
                                        } label: {
                                            Text("將所有已完成事項移入垃圾桶")
                                        }
                                    }
                                }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
    }
    
    private var addListSheet: some View {
        VStack(spacing: 16) {
            Text("新增待辦分類清單")
                .font(.appScale(15, weight: .bold))
            
            TextField("清單名稱 (例如：專案研發、個人閱讀)", text: $newListName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .font(.appScale(12))
                .frame(width: 260)
            
            HStack(spacing: 12) {
                Button("取消") {
                    showingAddListAlert = false
                }
                .keyboardShortcut(.cancelAction)
                
                Button("建立") {
                    dataManager.addList(title: newListName)
                    showingAddListAlert = false
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(BorderedProminentButtonStyle())
                .disabled(newListName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 320)
    }
    
    private var currentFilterTitle: String {
        switch dataManager.selectedFilter {
        case .pending: return "待辦中"
        case .today: return "今天到期"
        case .upcoming: return "即將到來"
        case .calendar: return "月份日曆"
        case .all: return "全部待辦"
        case .completed: return "已完成事項"
        case .trash: return "垃圾桶"
        case .list(let id):
            return dataManager.lists.first(where: { $0.id == id })?.title ?? "待辦清單"
        }
    }
    
    private func filterIconColor(_ filter: SmartFilterType) -> Color {
        switch filter {
        case .pending: return .accentColor
        case .today: return .orange
        case .upcoming: return .blue
        case .calendar: return .teal
        case .all: return .purple
        case .completed: return .green
        case .trash: return .red.opacity(0.8)
        case .list: return .secondary
        }
    }
    
    private func submitInlineTask() {
        let trimmed = quickAddInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        var due: Date? = nil
        if case .today = dataManager.selectedFilter {
            due = Date()
        }
        
        let created = dataManager.addTask(title: trimmed, due: due)
        dataManager.selectedTaskId = created.id
        quickAddInput = ""
    }
}

// MARK: - Proportional Resizing Divider

struct ProportionalDivider: View {
    let onDelta: (CGFloat) -> Void
    @State private var isHovering = false
    @State private var dragOffset: CGFloat = 0
    
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(isHovering ? 0.25 : 0.08))
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let delta = value.translation.width - dragOffset
                        dragOffset = value.translation.width
                        onDelta(delta)
                    }
                    .onEnded { _ in
                        dragOffset = 0
                    }
            )
    }
}

// Fallback for any other usages
struct DraggableDivider: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    @State private var isHovering = false
    
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(isHovering ? 0.2 : 0.08))
            .frame(width: 5)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newW = width + value.translation.width
                        width = min(max(newW, minWidth), maxWidth)
                    }
            )
    }
}

// MARK: - Drag & Drop Delegates for Filters, Lists & Tasks

struct SmartFilterDropDelegate: DropDelegate {
    let targetItem: SmartFilterType
    let dataManager: DataManager
    @Binding var draggingId: String?
    
    func dropEntered(info: DropInfo) {
        guard let sourceId = draggingId, sourceId != targetItem.id else { return }
        dataManager.moveSmartFilter(fromId: sourceId, toId: targetItem.id)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }
}

struct ListDropDelegate: DropDelegate {
    let targetItem: TaskList
    let dataManager: DataManager
    @Binding var draggingId: String?
    
    func dropEntered(info: DropInfo) {
        guard let sourceId = draggingId, sourceId != targetItem.id else { return }
        dataManager.moveList(fromId: sourceId, toId: targetItem.id)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }
}

struct TrashTaskRowView: View {
    let task: TaskItem
    let isSelected: Bool
    @ObservedObject private var dataManager = DataManager.shared
    
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "trash")
                .font(.appScale(12))
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.appScale(13, weight: isSelected ? .medium : .regular))
                    .strikethrough(task.isCompleted)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                if let del = task.deletedAt {
                    let daysLeft = max(0, 30 - (Calendar.current.dateComponents([.day], from: del, to: Date()).day ?? 0))
                    Text("刪除於 \(formatDeletedDate(del)) · 還有 \(daysLeft) 天自動清除")
                        .font(.appScale(10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Button("還原") {
                dataManager.restoreTask(taskId: task.id)
            }
            .font(.appScale(11))
            .buttonStyle(BorderedButtonStyle())
            .controlSize(.small)
            
            Button(action: {
                dataManager.permanentDeleteTask(taskId: task.id)
            }) {
                Image(systemName: "xmark")
                    .font(.appScale(10, weight: .bold))
                    .foregroundColor(.red.opacity(0.8))
                    .padding(4)
            }
            .buttonStyle(PlainButtonStyle())
            .help("永久刪除")
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(6)
    }
    
    private func formatDeletedDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: date)
    }
}

struct TaskDropDelegate: DropDelegate {
    let targetItem: TaskItem
    let dataManager: DataManager
    @Binding var draggingId: String?
    
    func dropEntered(info: DropInfo) {
        guard dataManager.sortOrder == .manual else { return }
        guard let sourceId = draggingId, sourceId != targetItem.id else { return }
        dataManager.moveTask(fromId: sourceId, toId: targetItem.id)
    }
    
    func performDrop(info: DropInfo) -> Bool {
        draggingId = nil
        return true
    }
}

// MARK: - Supporting Row Views

struct SmartFilterRow: View {
    let type: SmartFilterType
    let count: Int
    let iconColor: Color
    let isSelected: Bool
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: type.iconName)
                    .font(.appScale(13))
                    .foregroundColor(iconColor)
                    .frame(width: 18)
                
                Text(type.displayName)
                    .font(.appScale(13))
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.85))
                
                Spacer()
                
                if count > 0 {
                    Text("\(count)")
                        .font(.appScale(11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

struct ListRowView: View {
    let list: TaskList
    let count: Int
    let isSelected: Bool
    let action: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.appScale(9))
                    .foregroundColor(.secondary.opacity(0.4))
                
                Image(systemName: "list.bullet")
                    .font(.appScale(12))
                    .foregroundColor(.accentColor)
                    .frame(width: 16)
                
                Text(list.title)
                    .font(.appScale(13))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .primary : .primary.opacity(0.85))
                
                Spacer()
                
                if count > 0 {
                    Text("\(count)")
                        .font(.appScale(11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : (isHovered ? Color.primary.opacity(0.06) : Color.clear))
            )
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering in
            isHovered = hovering
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Text("刪除清單")
            }
        }
    }
}

struct TaskRowView: View {
    let task: TaskItem
    let isSelected: Bool
    @ObservedObject private var dataManager = DataManager.shared
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Drag handle indicator when in manual sort
            if dataManager.sortOrder == .manual {
                Image(systemName: "line.3.horizontal")
                    .font(.appScale(10))
                    .foregroundColor(.secondary.opacity(0.4))
                    .padding(.top, 4)
            }
            
            // Checkbox
            Button(action: {
                dataManager.toggleTaskCompletion(taskId: task.id)
            }) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.appScale(15))
                    .foregroundColor(task.isCompleted ? .secondary : .accentColor)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 2)
            
            VStack(alignment: .leading, spacing: 4) {
                // Title
                Text(task.title)
                    .font(.appScale(13, weight: isSelected ? .medium : .regular))
                    .strikethrough(task.isCompleted)
                    .foregroundColor(task.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                
                // Metadata chips (Due date, Subtasks, Notes)
                HStack(spacing: 6) {
                    if let due = task.due {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.appScale(9))
                            Text(formatDueDate(due))
                                .font(.appScale(10, weight: .medium))
                        }
                        .foregroundColor(dueDateColor(due, isCompleted: task.isCompleted))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(dueDateColor(due, isCompleted: task.isCompleted).opacity(0.12))
                        .cornerRadius(4)
                    }
                    
                    if !task.subtasks.isEmpty {
                        let comp = task.subtasks.filter { $0.isCompleted }.count
                        HStack(spacing: 3) {
                            Image(systemName: "list.bullet.indent")
                                .font(.appScale(9))
                            Text("\(comp)/\(task.subtasks.count)")
                                .font(.appScale(10))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(4)
                    }
                    
                    if task.notes != nil && !task.notes!.isEmpty {
                        Image(systemName: "text.alignleft")
                            .font(.appScale(10))
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        .cornerRadius(6)
    }
    
    private func formatDueDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "今天" }
        if cal.isDateInTomorrow(date) { return "明天" }
        if cal.isDateInYesterday(date) { return "已逾期" }
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }
    
    private func dueDateColor(_ date: Date, isCompleted: Bool) -> Color {
        if isCompleted { return .secondary }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return .orange }
        if cal.startOfDay(for: date) < cal.startOfDay(for: Date()) { return .red }
        return .blue
    }
}
