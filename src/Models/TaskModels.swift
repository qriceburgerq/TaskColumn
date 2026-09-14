import Foundation

public enum TaskStatus: String, Codable, CaseIterable {
    case needsAction = "needsAction"
    case completed = "completed"
    
    public var isCompleted: Bool {
        return self == .completed
    }
}

public struct TaskList: Identifiable, Hashable, Codable {
    public var id: String
    public var title: String
    public var updated: Date?
    
    public init(id: String = UUID().uuidString, title: String, updated: Date? = Date()) {
        self.id = id
        self.title = title
        self.updated = updated
    }
}

public struct TaskItem: Identifiable, Hashable, Codable {
    public var id: String
    public var listId: String
    public var title: String
    public var notes: String?
    public var due: Date?
    public var status: TaskStatus
    public var completedDate: Date?
    public var parent: String?
    public var position: String?
    public var subtasks: [TaskItem]
    public var updated: Date?
    public var deletedAt: Date?
    
    public init(
        id: String = UUID().uuidString,
        listId: String,
        title: String,
        notes: String? = nil,
        due: Date? = nil,
        status: TaskStatus = .needsAction,
        completedDate: Date? = nil,
        parent: String? = nil,
        position: String? = nil,
        subtasks: [TaskItem] = [],
        updated: Date? = Date(),
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.listId = listId
        self.title = title
        self.notes = notes
        self.due = due
        self.status = status
        self.completedDate = completedDate
        self.parent = parent
        self.position = position
        self.subtasks = subtasks
        self.updated = updated
        self.deletedAt = deletedAt
    }
    
    public var isCompleted: Bool {
        return status == .completed
    }
    
    public var isDeleted: Bool {
        return deletedAt != nil
    }
    
    public var isOverdue: Bool {
        guard let due = due, !isCompleted else { return false }
        return Calendar.current.startOfDay(for: due) < Calendar.current.startOfDay(for: Date())
    }
    
    public var isToday: Bool {
        guard let due = due else { return false }
        return Calendar.current.isDateInToday(due)
    }
    
    public var isUpcoming: Bool {
        guard let due = due, !isCompleted else { return false }
        let now = Date()
        let cal = Calendar.current
        guard let nextWeek = cal.date(byAdding: .day, value: 7, to: now) else { return false }
        let startToday = cal.startOfDay(for: now)
        let dueStart = cal.startOfDay(for: due)
        return dueStart >= startToday && dueStart <= nextWeek
    }
}

public enum SmartFilterType: Hashable, Identifiable, Codable {
    case pending
    case today
    case upcoming
    case calendar
    case all
    case completed
    case trash
    case list(id: String)
    
    public var id: String {
        switch self {
        case .pending: return "smart_pending"
        case .today: return "smart_today"
        case .upcoming: return "smart_upcoming"
        case .calendar: return "smart_calendar"
        case .all: return "smart_all"
        case .completed: return "smart_completed"
        case .trash: return "smart_trash"
        case .list(let id): return "list_\(id)"
        }
    }
    
    public var displayName: String {
        switch self {
        case .pending: return "待辦中"
        case .today: return "今天到期"
        case .upcoming: return "即將到來"
        case .calendar: return "月份日曆"
        case .all: return "全部待辦"
        case .completed: return "已完成事項"
        case .trash: return "垃圾桶"
        case .list: return "清單"
        }
    }
    
    public var iconName: String {
        switch self {
        case .pending: return "circle.dashed"
        case .today: return "star.fill"
        case .upcoming: return "calendar"
        case .calendar: return "calendar.badge.clock"
        case .all: return "tray.full.fill"
        case .completed: return "checkmark.circle.fill"
        case .trash: return "trash"
        case .list: return "list.bullet"
        }
    }
    
    public static func from(id: String) -> SmartFilterType? {
        switch id {
        case "smart_pending": return .pending
        case "smart_today": return .today
        case "smart_upcoming": return .upcoming
        case "smart_calendar": return .calendar
        case "smart_all": return .all
        case "smart_completed": return .completed
        case "smart_trash": return .trash
        default:
            if id.hasPrefix("list_") {
                let lid = String(id.dropFirst(5))
                return .list(id: lid)
            }
            return nil
        }
    }
}

public enum TaskSortOrder: String, CaseIterable, Identifiable {
    case manual = "自訂拖曳順序"
    case dueDate = "到期日優先"
    case creation = "建立順序"
    case title = "標題名稱"
    
    public var id: String { rawValue }
}
