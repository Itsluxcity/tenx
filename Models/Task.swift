import Foundation

struct TaskItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var description: String?
    var company: String?
    var assignee: String
    var createdAt: Date
    var dueDate: Date?
    var status: TaskStatus
    var sourceUtteranceId: String?
    var reminderIds: [String]
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String? = nil,
        company: String? = nil,
        assignee: String = "me",
        createdAt: Date = Date(),
        dueDate: Date? = nil,
        status: TaskStatus = .pending,
        sourceUtteranceId: String? = nil,
        reminderIds: [String] = []
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.company = company
        self.assignee = assignee
        self.createdAt = createdAt
        self.dueDate = dueDate
        self.status = status
        self.sourceUtteranceId = sourceUtteranceId
        self.reminderIds = reminderIds
    }
    
    var isOverdue: Bool {
        guard let dueDate = dueDate else { return false }
        return dueDate < Date() && status != .done && status != .cancelled
    }
}

enum TaskStatus: String, Codable {
    case pending
    case inProgress = "in_progress"
    case done
    case cancelled
}
