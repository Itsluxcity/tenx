import Foundation

class TaskManager {
    private let fileManager = FileManager.default
    private var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    private var tasksFile: URL {
        documentsURL.appendingPathComponent("tasks/tasks.json")
    }
    
    private var tasksLogFile: URL {
        documentsURL.appendingPathComponent("tasks/tasks-log.md")
    }
    
    func loadTasks() -> [TaskItem] {
        guard let data = try? Data(contentsOf: tasksFile) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        return (try? decoder.decode([TaskItem].self, from: data)) ?? []
    }
    
    func saveTasks(_ tasks: [TaskItem]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        
        if let data = try? encoder.encode(tasks) {
            try? data.write(to: tasksFile)
        }
    }
    
    func createOrUpdateTask(_ task: TaskItem) {
        var tasks = loadTasks()
        
        if let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index] = task
            logTaskUpdate(task, action: "Updated")
        } else {
            tasks.append(task)
            logTaskUpdate(task, action: "Created")
        }
        
        saveTasks(tasks)
    }
    
    func toggleTaskComplete(taskId: String) {
        var tasks = loadTasks()
        
        if let index = tasks.firstIndex(where: { $0.id.uuidString == taskId }) {
            // Toggle between done and pending
            if tasks[index].status == .done {
                tasks[index].status = .pending
                logTaskUpdate(tasks[index], action: "Reopened")
            } else {
                tasks[index].status = .done
                logTaskUpdate(tasks[index], action: "Completed")
            }
            saveTasks(tasks)
        }
    }
    
    // Keep old method for compatibility
    func markTaskComplete(taskId: String) {
        toggleTaskComplete(taskId: taskId)
    }
    
    func deleteTask(taskId: String) {
        var tasks = loadTasks()
        
        if let index = tasks.firstIndex(where: { $0.id.uuidString == taskId }) {
            let task = tasks[index]
            tasks.remove(at: index)
            saveTasks(tasks)
            logTaskUpdate(task, action: "Deleted")
        }
    }
    
    func updateTaskDueDate(taskId: String, dueDate: Date) {
        var tasks = loadTasks()
        
        if let index = tasks.firstIndex(where: { $0.id.uuidString == taskId }) {
            tasks[index].dueDate = dueDate
            saveTasks(tasks)
            logTaskUpdate(tasks[index], action: "Updated due date")
        }
    }
    
    private func logTaskUpdate(_ task: TaskItem, action: String) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let timestamp = dateFormatter.string(from: Date())
        let dueDateStr = task.dueDate.map { dateFormatter.string(from: $0) } ?? "No due date"
        
        let logEntry = """
        
        ### [\(timestamp)] \(action): \(task.title)
        - Status: \(task.status.rawValue)
        - Assignee: \(task.assignee)
        - Due Date: \(dueDateStr)
        \(task.company.map { "- Company: \($0)" } ?? "")
        \(task.description.map { "- Description: \($0)" } ?? "")
        
        """
        
        if let handle = try? FileHandle(forWritingTo: tasksLogFile) {
            handle.seekToEndOfFile()
            handle.write(logEntry.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? logEntry.write(to: tasksLogFile, atomically: true, encoding: .utf8)
        }
    }
}
