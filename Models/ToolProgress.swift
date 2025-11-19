import Foundation

struct ToolProgress: Identifiable {
    let id = UUID()
    let toolName: String
    let description: String
    var status: ToolStatus
    var attachment: MessageAttachment?
    
    enum ToolStatus {
        case pending
        case inProgress
        case completed
        case failed
    }
    
    var icon: String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
}
