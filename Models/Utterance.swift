import Foundation

struct Utterance: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let sessionId: String
    let text: String
    var status: UtteranceStatus
    
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        sessionId: String,
        text: String,
        status: UtteranceStatus
    ) {
        self.id = id
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.text = text
        self.status = status
    }
}

enum UtteranceStatus: String, Codable {
    case pending
    case processing
    case done
    case error
}
