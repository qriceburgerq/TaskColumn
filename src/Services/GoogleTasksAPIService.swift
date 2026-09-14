import Foundation

@MainActor
public class GoogleTasksAPIService {
    public static let shared = GoogleTasksAPIService()
    private let authService = GoogleAuthService.shared
    private let baseURL = "https://tasks.googleapis.com/tasks/v1"
    
    private let rfc3339DateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private let fallbackDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
    
    private init() {}
    
    private func makeRequest(endpoint: String, method: String = "GET", body: [String: Any]? = nil) async throws -> (Data, HTTPURLResponse) {
        let token = try await authService.getValidAccessToken()
        guard let url = URL(string: "\(baseURL)/\(endpoint)") else {
            throw URLError(.badURL)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let body = body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        return (data, httpResponse)
    }
    
    public func fetchTaskLists() async throws -> [TaskList] {
        let (data, response) = try await makeRequest(endpoint: "users/@me/lists")
        guard response.statusCode == 200 else {
            throw NSError(domain: "GoogleTasksAPI", code: response.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "取得清單失敗: HTTP \(response.statusCode)"
            ])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }
        
        return items.compactMap { dict -> TaskList? in
            guard let id = dict["id"] as? String, let title = dict["title"] as? String else { return nil }
            var updatedDate: Date? = nil
            if let updatedStr = dict["updated"] as? String {
                updatedDate = self.parseDate(updatedStr)
            }
            return TaskList(id: id, title: title, updated: updatedDate)
        }
    }
    
    public func fetchTasks(listId: String) async throws -> [TaskItem] {
        let endpoint = "lists/\(listId)/tasks?showCompleted=true&showHidden=true&maxResults=100"
        let (data, response) = try await makeRequest(endpoint: endpoint)
        guard response.statusCode == 200 else {
            throw NSError(domain: "GoogleTasksAPI", code: response.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "取得任務失敗: HTTP \(response.statusCode)"
            ])
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["items"] as? [[String: Any]] else {
            return []
        }
        
        var parsedTasks: [TaskItem] = []
        for dict in items {
            guard let id = dict["id"] as? String, let title = dict["title"] as? String else { continue }
            let notes = dict["notes"] as? String
            let statusStr = dict["status"] as? String ?? "needsAction"
            let status = TaskStatus(rawValue: statusStr) ?? .needsAction
            let parent = dict["parent"] as? String
            let position = dict["position"] as? String
            
            var dueDate: Date? = nil
            if let dueStr = dict["due"] as? String {
                dueDate = self.parseDate(dueStr)
            }
            
            var completedDate: Date? = nil
            if let compStr = dict["completed"] as? String {
                completedDate = self.parseDate(compStr)
            }
            
            var updatedDate: Date? = nil
            if let upStr = dict["updated"] as? String {
                updatedDate = self.parseDate(upStr)
            }
            
            let task = TaskItem(
                id: id,
                listId: listId,
                title: title,
                notes: notes,
                due: dueDate,
                status: status,
                completedDate: completedDate,
                parent: parent,
                position: position,
                subtasks: [],
                updated: updatedDate
            )
            parsedTasks.append(task)
        }
        
        return parsedTasks
    }
    
    public func createTask(listId: String, title: String, notes: String?, due: Date?, parentId: String?) async throws -> TaskItem {
        var body: [String: Any] = ["title": title]
        if let notes = notes, !notes.isEmpty {
            body["notes"] = notes
        }
        if let due = due {
            body["due"] = rfc3339DateFormatter.string(from: due)
        }
        
        var endpoint = "lists/\(listId)/tasks"
        if let parentId = parentId, !parentId.isEmpty {
            endpoint += "?parent=\(parentId)"
        }
        
        let (data, response) = try await makeRequest(endpoint: endpoint, method: "POST", body: body)
        guard response.statusCode == 200 || response.statusCode == 201 else {
            throw NSError(domain: "GoogleTasksAPI", code: response.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "建立任務失敗: HTTP \(response.statusCode)"
            ])
        }
        
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = dict["id"] as? String else {
            throw NSError(domain: "GoogleTasksAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "建立任務回傳格式錯誤"])
        }
        
        return TaskItem(
            id: id,
            listId: listId,
            title: title,
            notes: notes,
            due: due,
            status: .needsAction,
            parent: parentId,
            updated: Date()
        )
    }
    
    public func updateTask(listId: String, task: TaskItem) async throws -> TaskItem {
        var body: [String: Any] = [
            "id": task.id,
            "title": task.title,
            "status": task.status.rawValue
        ]
        if let notes = task.notes {
            body["notes"] = notes
        }
        if let due = task.due {
            body["due"] = rfc3339DateFormatter.string(from: due)
        }
        
        let (_, response) = try await makeRequest(endpoint: "lists/\(listId)/tasks/\(task.id)", method: "PATCH", body: body)
        guard response.statusCode == 200 else {
            throw NSError(domain: "GoogleTasksAPI", code: response.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "更新任務失敗: HTTP \(response.statusCode)"
            ])
        }
        
        return task
    }
    
    public func deleteTask(listId: String, taskId: String) async throws {
        let (_, response) = try await makeRequest(endpoint: "lists/\(listId)/tasks/\(taskId)", method: "DELETE")
        guard response.statusCode == 200 || response.statusCode == 204 else {
            throw NSError(domain: "GoogleTasksAPI", code: response.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "刪除任務失敗: HTTP \(response.statusCode)"
            ])
        }
    }
    
    public func createTaskList(title: String) async throws -> TaskList {
        let (data, response) = try await makeRequest(endpoint: "users/@me/lists", method: "POST", body: ["title": title])
        guard response.statusCode == 200 || response.statusCode == 201 else {
            throw NSError(domain: "GoogleTasksAPI", code: response.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "建立清單失敗: HTTP \(response.statusCode)"
            ])
        }
        
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = dict["id"] as? String else {
            throw NSError(domain: "GoogleTasksAPI", code: 500, userInfo: [NSLocalizedDescriptionKey: "建立清單回傳格式錯誤"])
        }
        
        return TaskList(id: id, title: title, updated: Date())
    }
    
    public func deleteTaskList(listId: String) async throws {
        let (_, response) = try await makeRequest(endpoint: "users/@me/lists/\(listId)", method: "DELETE")
        guard response.statusCode == 200 || response.statusCode == 204 else {
            throw NSError(domain: "GoogleTasksAPI", code: response.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "刪除清單失敗: HTTP \(response.statusCode)"
            ])
        }
    }
    
    private func parseDate(_ dateStr: String) -> Date? {
        if let d = rfc3339DateFormatter.date(from: dateStr) {
            return d
        }
        return fallbackDateFormatter.date(from: dateStr)
    }
}
