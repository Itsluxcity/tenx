import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: MessageRole
    let content: String
    let timestamp: Date
    var attachments: [MessageAttachment]?
    
    init(id: UUID = UUID(), role: MessageRole, content: String, timestamp: Date = Date(), attachments: [MessageAttachment]? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.attachments = attachments
    }
}

struct MessageAttachment: Identifiable, Codable {
    let id: UUID
    let type: AttachmentType
    let title: String
    let subtitle: String?
    let actionData: String // Store reminder ID or calendar event ID
    
    init(id: UUID = UUID(), type: AttachmentType, title: String, subtitle: String? = nil, actionData: String) {
        self.id = id
        self.type = type
        self.title = title
        self.subtitle = subtitle
        self.actionData = actionData
    }
}

enum AttachmentType: String, Codable {
    case reminder
    case calendarEvent
    case task
}

enum MessageRole: String, Codable {
    case user
    case assistant
}
