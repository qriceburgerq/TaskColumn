import Foundation
import Combine
import SwiftUI

@MainActor
public class DataManager: ObservableObject {
    public static let shared = DataManager()
    
    @Published public var lists: [TaskList] = []
    @Published public var allTasks: [TaskItem] = []
    @Published public var trashTasks: [TaskItem] = []
    
    @Published public var selectedFilter: SmartFilterType = .all
    @Published public var selectedTaskId: String? = nil
    @Published public var searchQuery: String = ""
    @Published public var sortOrder: TaskSortOrder = .manual
    
    // Smart Filter Ordering
    public static let defaultSmartFilterOrder: [String] = [
        "smart_pending", "smart_today", "smart_upcoming", "smart_calendar", "smart_all", "smart_completed", "smart_trash"
    ]
    @Published public var smartFilterOrder: [String] = DataManager.defaultSmartFilterOrder
    
    // Font Scaling
    @Published public var fontScale: Double {
        didSet {
            UserDefaults.standard.set(fontScale, forKey: "app_font_scale")
        }
    }
    
    @Published public var isSyncing: Bool = false
    @Published public var lastSyncTime: Date? = nil
    @Published public var syncErrorMessage: String? = nil
    
    private let authService = GoogleAuthService.shared
    private let apiService = GoogleTasksAPIService.shared
    
    private var saveURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("TaskColumn", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
        return dir.appendingPathComponent("tasks_store.json")
    }
    
    private struct StorageData: Codable {
        var lists: [TaskList]
        var tasks: [TaskItem]
        var trashTasks: [TaskItem]?
        var smartFilterOrder: [String]?
        var lastSync: Date?
    }
    
    private init() {
        let savedScale = UserDefaults.standard.double(forKey: "app_font_scale")
        self.fontScale = savedScale > 0.5 ? savedScale : 1.0
        
        loadFromDisk()
        purgeOldTrash()
        if lists.isEmpty {
            createInitialData()
        }
    }
    
    // MARK: - Zoom Controls
    
    public func zoomIn() {
        let next = (fontScale * 10 + 1).rounded() / 10.0
        fontScale = min(next, 1.5)
    }
    
    public func zoomOut() {
        let prev = (fontScale * 10 - 1).rounded() / 10.0
        fontScale = max(prev, 0.8)
    }
    
    public func resetZoom() {
        fontScale = 1.0
    }
    
    public func setZoom(_ scale: Double) {
        fontScale = min(max(scale, 0.8), 1.5)
    }
    
    public func scaledFontSize(_ base: CGFloat) -> CGFloat {
        return max(9, round(base * CGFloat(fontScale)))
    }
    
    // MARK: - Local Persistence
    
    private func saveToDisk() {
        let storage = StorageData(
            lists: lists,
            tasks: allTasks,
            trashTasks: trashTasks,
            smartFilterOrder: smartFilterOrder,
            lastSync: lastSyncTime
        )
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(storage)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            print("Failed to save tasks to disk: \(error)")
        }
    }
    
    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: saveURL.path) else { return }
        do {
            let data = try Data(contentsOf: saveURL)
            let decoder = JSONDecoder()
            let storage = try decoder.decode(StorageData.self, from: data)
            self.lists = storage.lists
            self.allTasks = storage.tasks
            self.trashTasks = storage.trashTasks ?? []
            if let order = storage.smartFilterOrder, !order.isEmpty {
                self.smartFilterOrder = order
            }
            self.lastSyncTime = storage.lastSync
        } catch {
            print("Failed to load tasks from disk: \(error)")
        }
    }
    
    private func createInitialData() {
        let defaultList = TaskList(id: "default_list", title: "主要清單 (預設)")
        let workList = TaskList(id: "work_list", title: "💼 工作與專案")
        let personalList = TaskList(id: "personal_list", title: "🌱 個人生活")
        self.lists = [defaultList, workList, personalList]
        
        let now = Date()
        let cal = Calendar.current
        let today = now
        let tomorrow = cal.date(byAdding: .day, value: 1, to: now)
        let nextWeek = cal.date(byAdding: .day, value: 3, to: now)
        
        let task1 = TaskItem(
            id: UUID().uuidString,
            listId: defaultList.id,
            title: "歡迎使用 TaskColumn！體驗 macOS 直欄待辦",
            notes: "點選右側直欄即可查看備忘筆記，並能自由新增階層子任務。\n支援完全離線操作與 Google Tasks 雙向同步！",
            due: today,
            status: .needsAction,
            subtasks: [
                TaskItem(listId: defaultList.id, title: "點選左側切換清單與智慧篩選", status: .completed),
                TaskItem(listId: defaultList.id, title: "在第二欄點選待辦查看右側直欄階層", status: .needsAction),
                TaskItem(listId: defaultList.id, title: "嘗試在此處新增一項子任務", status: .needsAction)
            ]
        )
        
        let task2 = TaskItem(
            id: UUID().uuidString,
            listId: defaultList.id,
            title: "隨時按下 Command + Shift + A 呼叫全域快速新增",
            notes: "即使你在 Safari、Slack 或任何全螢幕應用，隨時按下全域快捷鍵即可快速新增任務！可在偏好設定中自訂按鍵。",
            due: today,
            status: .needsAction
        )
        
        let task3 = TaskItem(
            id: UUID().uuidString,
            listId: workList.id,
            title: "在頂部選單列 (Menu Bar) 查看今日未完成數量",
            notes: "點擊右上角狀態列圖示，不用切換視窗就能直接預覽今日任務並打勾完成！",
            due: tomorrow,
            status: .needsAction
        )
        
        let task4 = TaskItem(
            id: UUID().uuidString,
            listId: personalList.id,
            title: "點擊「登入 Google 帳號」一鍵完成 OAuth 綁定",
            notes: "現在支援一鍵自動呼叫瀏覽器登入，資料直接與 Google 伺服器傳輸，無需手動填寫複雜的 Client 憑證。",
            due: nextWeek,
            status: .needsAction
        )
        
        self.allTasks = [task1, task2, task3, task4]
        self.selectedTaskId = task1.id
        saveToDisk()
    }
    
    // MARK: - Computed Filtered Tasks
    
    public var currentFilteredTasks: [TaskItem] {
        var baseTasks: [TaskItem] = []
        
        switch selectedFilter {
        case .pending:
            baseTasks = allTasks.filter { $0.parent == nil && !$0.isCompleted }
        case .today:
            baseTasks = allTasks.filter { $0.parent == nil && ($0.isToday || $0.isOverdue) }
        case .upcoming:
            baseTasks = allTasks.filter { $0.parent == nil && $0.isUpcoming }
        case .calendar:
            baseTasks = allTasks.filter { $0.parent == nil && $0.due != nil }
        case .all:
            baseTasks = allTasks.filter { $0.parent == nil }
        case .completed:
            baseTasks = allTasks.filter { $0.parent == nil && $0.isCompleted }
        case .trash:
            baseTasks = trashTasks
        case .list(let listId):
            baseTasks = allTasks.filter { $0.parent == nil && $0.listId == listId }
        }
        
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let q = searchQuery.lowercased()
            baseTasks = baseTasks.filter { task in
                task.title.lowercased().contains(q) ||
                (task.notes?.lowercased().contains(q) ?? false) ||
                task.subtasks.contains(where: { $0.title.lowercased().contains(q) })
            }
        }
        
        switch sortOrder {
        case .manual:
            // Keep current manual sequence as stored in allTasks
            break
        case .dueDate:
            baseTasks.sort { (t1, t2) -> Bool in
                if t1.isCompleted != t2.isCompleted {
                    return !t1.isCompleted
                }
                guard let d1 = t1.due else { return false }
                guard let d2 = t2.due else { return true }
                return d1 < d2
            }
        case .creation:
            baseTasks.sort { (t1, t2) -> Bool in
                if t1.isCompleted != t2.isCompleted {
                    return !t1.isCompleted
                }
                guard let u1 = t1.updated else { return false }
                guard let u2 = t2.updated else { return true }
                return u1 > u2
            }
        case .title:
            baseTasks.sort { (t1, t2) -> Bool in
                if t1.isCompleted != t2.isCompleted {
                    return !t1.isCompleted
                }
                return t1.title.localizedCompare(t2.title) == .orderedAscending
            }
        }
        
        return baseTasks
    }
    
    public var selectedTask: TaskItem? {
        guard let id = selectedTaskId else { return nil }
        if let t = allTasks.first(where: { $0.id == id }) {
            return t
        }
        return trashTasks.first(where: { $0.id == id })
    }
    
    public var todayPendingTasks: [TaskItem] {
        return allTasks.filter { $0.parent == nil && !$0.isCompleted && ($0.isToday || $0.isOverdue) }
    }
    
    public var allPendingTasks: [TaskItem] {
        return allTasks.filter { $0.parent == nil && !$0.isCompleted }
    }
    
    public var todayPendingCount: Int {
        return todayPendingTasks.count
    }
    
    public func count(for filter: SmartFilterType) -> Int {
        switch filter {
        case .pending:
            return allTasks.filter { $0.parent == nil && !$0.isCompleted }.count
        case .today:
            return allTasks.filter { $0.parent == nil && !$0.isCompleted && ($0.isToday || $0.isOverdue) }.count
        case .upcoming:
            return allTasks.filter { $0.parent == nil && !$0.isCompleted && $0.isUpcoming }.count
        case .calendar:
            return allTasks.filter { $0.parent == nil && $0.due != nil && !$0.isCompleted }.count
        case .all:
            return allTasks.filter { $0.parent == nil && !$0.isCompleted }.count
        case .completed:
            return allTasks.filter { $0.parent == nil && $0.isCompleted }.count
        case .trash:
            return trashTasks.count
        case .list(let id):
            return allTasks.filter { $0.parent == nil && $0.listId == id && !$0.isCompleted }.count
        }
    }
    
    public var smartFilters: [SmartFilterType] {
        var result: [SmartFilterType] = []
        for id in smartFilterOrder {
            if let f = SmartFilterType.from(id: id) {
                result.append(f)
            }
        }
        let allDefaults: [SmartFilterType] = [.pending, .today, .upcoming, .calendar, .all, .completed, .trash]
        for d in allDefaults {
            if !result.contains(d) {
                result.append(d)
            }
        }
        return result
    }
    
    public func moveSmartFilter(fromId: String, toId: String) {
        var currentOrder = smartFilters.map { $0.id }
        guard let fromIndex = currentOrder.firstIndex(of: fromId),
              let toIndex = currentOrder.firstIndex(of: toId),
              fromIndex != toIndex else { return }
        let item = currentOrder.remove(at: fromIndex)
        currentOrder.insert(item, at: toIndex)
        self.smartFilterOrder = currentOrder
        saveToDisk()
    }
    
    public func purgeOldTrash() {
        let now = Date()
        let thirtyDaysAgo = now.addingTimeInterval(-30 * 86400)
        trashTasks.removeAll { task in
            if let d = task.deletedAt {
                return d < thirtyDaysAgo
            }
            return false
        }
        saveToDisk()
    }
    
    // MARK: - Drag & Drop Reordering
    
    public func moveList(fromOffsets indices: IndexSet, toOffset destination: Int) {
        lists.move(fromOffsets: indices, toOffset: destination)
        saveToDisk()
    }
    
    public func moveList(fromId: String, toId: String) {
        guard let fromIndex = lists.firstIndex(where: { $0.id == fromId }),
              let toIndex = lists.firstIndex(where: { $0.id == toId }),
              fromIndex != toIndex else { return }
        let item = lists.remove(at: fromIndex)
        lists.insert(item, at: toIndex)
        saveToDisk()
    }
    
    public func moveTasks(fromOffsets indices: IndexSet, toOffset destination: Int) {
        allTasks.move(fromOffsets: indices, toOffset: destination)
        saveToDisk()
    }
    
    public func moveTask(fromId: String, toId: String) {
        guard let fromIndex = allTasks.firstIndex(where: { $0.id == fromId }),
              let toIndex = allTasks.firstIndex(where: { $0.id == toId }),
              fromIndex != toIndex else { return }
        let item = allTasks.remove(at: fromIndex)
        allTasks.insert(item, at: toIndex)
        saveToDisk()
    }
    
    // MARK: - Task Mutations
    
    public func addTask(
        listId: String? = nil,
        title: String,
        notes: String? = nil,
        due: Date? = nil,
        parentId: String? = nil
    ) -> TaskItem {
        let targetListId: String
        if let lid = listId {
            targetListId = lid
        } else if case .list(let currentLid) = selectedFilter {
            targetListId = currentLid
        } else {
            targetListId = lists.first?.id ?? "default"
        }
        
        let newTask = TaskItem(
            id: UUID().uuidString,
            listId: targetListId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes?.trimmingCharacters(in: .whitespacesAndNewlines),
            due: due,
            status: .needsAction,
            parent: parentId,
            subtasks: [],
            updated: Date()
        )
        
        if let parentId = parentId, let pIndex = allTasks.firstIndex(where: { $0.id == parentId }) {
            allTasks[pIndex].subtasks.append(newTask)
        } else {
            allTasks.insert(newTask, at: 0)
        }
        
        saveToDisk()
        
        if authService.isAuthenticated {
            Task {
                do {
                    let created = try await apiService.createTask(
                        listId: targetListId,
                        title: newTask.title,
                        notes: newTask.notes,
                        due: newTask.due,
                        parentId: parentId
                    )
                    await MainActor.run {
                        if let idx = self.allTasks.firstIndex(where: { $0.id == newTask.id }) {
                            self.allTasks[idx].id = created.id
                            if self.selectedTaskId == newTask.id {
                                self.selectedTaskId = created.id
                            }
                        }
                        self.saveToDisk()
                    }
                } catch {
                    print("Google Tasks sync create task failed: \(error)")
                }
            }
        }
        
        return newTask
    }
    
    public func toggleTaskCompletion(taskId: String) {
        if let idx = allTasks.firstIndex(where: { $0.id == taskId }) {
            allTasks[idx].status = (allTasks[idx].status == .completed) ? .needsAction : .completed
            allTasks[idx].completedDate = (allTasks[idx].status == .completed) ? Date() : nil
            allTasks[idx].updated = Date()
            
            let updatedTask = allTasks[idx]
            saveToDisk()
            
            if authService.isAuthenticated {
                Task {
                    _ = try? await apiService.updateTask(listId: updatedTask.listId, task: updatedTask)
                }
            }
            return
        }
        
        // Check subtasks
        for pIdx in 0..<allTasks.count {
            if let sIdx = allTasks[pIdx].subtasks.firstIndex(where: { $0.id == taskId }) {
                allTasks[pIdx].subtasks[sIdx].status = (allTasks[pIdx].subtasks[sIdx].status == .completed) ? .needsAction : .completed
                allTasks[pIdx].subtasks[sIdx].updated = Date()
                saveToDisk()
                return
            }
        }
    }
    
    public func updateTask(_ task: TaskItem) {
        if let idx = allTasks.firstIndex(where: { $0.id == task.id }) {
            allTasks[idx] = task
            allTasks[idx].updated = Date()
            saveToDisk()
            
            if authService.isAuthenticated {
                Task {
                    _ = try? await apiService.updateTask(listId: task.listId, task: task)
                }
            }
            return
        }
        
        // Search subtasks
        for pIdx in 0..<allTasks.count {
            if let sIdx = allTasks[pIdx].subtasks.firstIndex(where: { $0.id == task.id }) {
                allTasks[pIdx].subtasks[sIdx] = task
                allTasks[pIdx].subtasks[sIdx].updated = Date()
                saveToDisk()
                return
            }
        }
    }
    
    public func deleteTask(taskId: String) {
        if let idx = allTasks.firstIndex(where: { $0.id == taskId }) {
            var task = allTasks.remove(at: idx)
            task.deletedAt = Date()
            trashTasks.insert(task, at: 0)
            if selectedTaskId == taskId {
                selectedTaskId = nil
            }
            saveToDisk()
            
            if authService.isAuthenticated {
                Task {
                    try? await apiService.deleteTask(listId: task.listId, taskId: taskId)
                }
            }
            return
        }
        
        // Remove from subtasks
        for pIdx in 0..<allTasks.count {
            if let sIdx = allTasks[pIdx].subtasks.firstIndex(where: { $0.id == taskId }) {
                var sub = allTasks[pIdx].subtasks.remove(at: sIdx)
                sub.deletedAt = Date()
                trashTasks.insert(sub, at: 0)
                saveToDisk()
                
                if authService.isAuthenticated {
                    Task {
                        try? await apiService.deleteTask(listId: sub.listId, taskId: taskId)
                    }
                }
                return
            }
        }
    }
    
    public func restoreTask(taskId: String) {
        guard let idx = trashTasks.firstIndex(where: { $0.id == taskId }) else { return }
        var restored = trashTasks.remove(at: idx)
        restored.deletedAt = nil
        restored.updated = Date()
        allTasks.insert(restored, at: 0)
        selectedTaskId = restored.id
        saveToDisk()
        
        if authService.isAuthenticated {
            Task {
                do {
                    let created = try await apiService.createTask(
                        listId: restored.listId,
                        title: restored.title,
                        notes: restored.notes,
                        due: restored.due,
                        parentId: restored.parent
                    )
                    await MainActor.run {
                        if let curIdx = self.allTasks.firstIndex(where: { $0.id == restored.id }) {
                            self.allTasks[curIdx].id = created.id
                            if self.selectedTaskId == restored.id {
                                self.selectedTaskId = created.id
                            }
                        }
                        self.saveToDisk()
                    }
                } catch {
                    print("Restore task sync failed: \(error)")
                }
            }
        }
    }
    
    public func permanentDeleteTask(taskId: String) {
        trashTasks.removeAll(where: { $0.id == taskId })
        if selectedTaskId == taskId {
            selectedTaskId = nil
        }
        saveToDisk()
    }
    
    public func emptyTrash() {
        trashTasks.removeAll()
        if case .trash = selectedFilter {
            selectedTaskId = nil
        }
        saveToDisk()
    }
    
    public func trashAllCompletedTasks() {
        let now = Date()
        let toTrash = allTasks.filter { $0.isCompleted }
        guard !toTrash.isEmpty else { return }
        
        allTasks.removeAll { $0.isCompleted }
        for var t in toTrash {
            t.deletedAt = now
            trashTasks.insert(t, at: 0)
        }
        
        if let sel = selectedTaskId, toTrash.contains(where: { $0.id == sel }) {
            selectedTaskId = nil
        }
        saveToDisk()
        
        if authService.isAuthenticated {
            Task {
                for t in toTrash {
                    try? await apiService.deleteTask(listId: t.listId, taskId: t.id)
                }
            }
        }
    }
    
    public func addSubtask(parentTaskId: String, title: String) {
        guard let pIdx = allTasks.firstIndex(where: { $0.id == parentTaskId }) else { return }
        let sub = TaskItem(
            id: UUID().uuidString,
            listId: allTasks[pIdx].listId,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            parent: parentTaskId,
            updated: Date()
        )
        allTasks[pIdx].subtasks.append(sub)
        saveToDisk()
        
        if authService.isAuthenticated {
            Task {
                do {
                    let created = try await apiService.createTask(
                        listId: sub.listId,
                        title: sub.title,
                        notes: nil,
                        due: nil,
                        parentId: parentTaskId
                    )
                    await MainActor.run {
                        if let curPIdx = self.allTasks.firstIndex(where: { $0.id == parentTaskId }),
                           let curSIdx = self.allTasks[curPIdx].subtasks.firstIndex(where: { $0.id == sub.id }) {
                            self.allTasks[curPIdx].subtasks[curSIdx].id = created.id
                        }
                        self.saveToDisk()
                    }
                } catch {
                    print("Google Tasks sync create subtask failed: \(error)")
                }
            }
        }
    }
    
    public func moveTask(taskId: String, toListId: String) {
        guard let idx = allTasks.firstIndex(where: { $0.id == taskId }) else { return }
        let oldListId = allTasks[idx].listId
        guard oldListId != toListId else { return }
        
        allTasks[idx].listId = toListId
        allTasks[idx].updated = Date()
        saveToDisk()
        
        if authService.isAuthenticated {
            Task {
                let task = self.allTasks[idx]
                try? await self.apiService.deleteTask(listId: oldListId, taskId: taskId)
                let created = try? await self.apiService.createTask(
                    listId: toListId,
                    title: task.title,
                    notes: task.notes,
                    due: task.due,
                    parentId: nil
                )
                if let created = created {
                    await MainActor.run {
                        if let curIdx = self.allTasks.firstIndex(where: { $0.id == taskId }) {
                            self.allTasks[curIdx].id = created.id
                            if self.selectedTaskId == taskId {
                                self.selectedTaskId = created.id
                            }
                        }
                        self.saveToDisk()
                    }
                }
            }
        }
    }
    
    // MARK: - List Management
    
    public func addList(title: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let newList = TaskList(id: UUID().uuidString, title: cleanTitle)
        self.lists.append(newList)
        self.selectedFilter = .list(id: newList.id)
        saveToDisk()
        
        if authService.isAuthenticated {
            Task {
                do {
                    let created = try await apiService.createTaskList(title: cleanTitle)
                    await MainActor.run {
                        if let idx = self.lists.firstIndex(where: { $0.id == newList.id }) {
                            self.lists[idx].id = created.id
                            if case .list(let curLid) = self.selectedFilter, curLid == newList.id {
                                self.selectedFilter = .list(id: created.id)
                            }
                        }
                        self.saveToDisk()
                    }
                } catch {
                    print("Google Tasks sync create list failed: \(error)")
                }
            }
        }
    }
    
    public func deleteList(id: String) {
        guard lists.count > 1 else { return }
        lists.removeAll(where: { $0.id == id })
        allTasks.removeAll(where: { $0.listId == id })
        if case .list(let curLid) = selectedFilter, curLid == id {
            selectedFilter = .all
        }
        saveToDisk()
        
        if authService.isAuthenticated {
            Task {
                try? await apiService.deleteTaskList(listId: id)
            }
        }
    }
    
    // MARK: - Google Sync
    
    public func syncWithGoogle() {
        guard authService.isAuthenticated else {
            syncErrorMessage = "尚未登入 Google 帳號"
            return
        }
        
        guard !isSyncing else { return }
        isSyncing = true
        syncErrorMessage = nil
        
        Task {
            do {
                let remoteLists = try await apiService.fetchTaskLists()
                var collectedTasks: [TaskItem] = []
                
                for list in remoteLists {
                    let tasks = try await apiService.fetchTasks(listId: list.id)
                    collectedTasks.append(contentsOf: tasks)
                }
                
                // Group tasks by parent
                var topLevelTasks: [TaskItem] = []
                let subtaskDict = Dictionary(grouping: collectedTasks.filter { $0.parent != nil }, by: { $0.parent! })
                
                for var task in collectedTasks where task.parent == nil {
                    if let subs = subtaskDict[task.id] {
                        task.subtasks = subs
                    }
                    topLevelTasks.append(task)
                }
                
                await MainActor.run {
                    self.lists = remoteLists
                    self.allTasks = topLevelTasks
                    self.lastSyncTime = Date()
                    self.isSyncing = false
                    self.saveToDisk()
                }
            } catch {
                await MainActor.run {
                    self.syncErrorMessage = error.localizedDescription
                    self.isSyncing = false
                }
            }
        }
    }
}

extension Font {
    @MainActor
    public static func appScale(_ size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        let scale = DataManager.shared.fontScale
        return .system(size: max(9, round(size * CGFloat(scale))), weight: weight, design: design)
    }
}
