import Foundation

struct Person: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var aliases: [String] // AKA / other spellings
    var summary: String?
    var role: String?
    var company: String?
    var lastContact: Date?
    var interactions: [PersonInteraction]
    var actionItems: [String]
    var keyTopics: [String]
    var createdAt: Date
    var updatedAt: Date
    
    init(
        id: UUID = UUID(),
        name: String,
        aliases: [String] = [],
        summary: String? = nil,
        role: String? = nil,
        company: String? = nil,
        lastContact: Date? = nil,
        interactions: [PersonInteraction] = [],
        actionItems: [String] = [],
        keyTopics: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.aliases = aliases
        self.summary = summary
        self.role = role
        self.company = company
        self.lastContact = lastContact
        self.interactions = interactions
        self.actionItems = actionItems
        self.keyTopics = keyTopics
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
    
    // Custom decoder to handle legacy files without aliases field
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // Default to empty array if aliases field doesn't exist (backward compatibility)
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        company = try container.decodeIfPresent(String.self, forKey: .company)
        lastContact = try container.decodeIfPresent(Date.self, forKey: .lastContact)
        interactions = try container.decode([PersonInteraction].self, forKey: .interactions)
        actionItems = try container.decode([String].self, forKey: .actionItems)
        keyTopics = try container.decode([String].self, forKey: .keyTopics)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
    
    var fileName: String {
        // Convert name to safe filename (lowercase, no spaces)
        return name.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
    }
}

struct PersonInteraction: Identifiable, Codable, Hashable {
    let id: UUID
    var date: Date
    var time: String
    var content: String
    var type: InteractionType
    
    init(
        id: UUID = UUID(),
        date: Date,
        time: String,
        content: String,
        type: InteractionType = .note
    ) {
        self.id = id
        self.date = date
        self.time = time
        self.content = content
        self.type = type
    }
    
    enum InteractionType: String, Codable {
        case meeting = "Meeting"
        case call = "Call"
        case message = "Message"
        case note = "Note"
        case email = "Email"
    }
}

// Index to track all people
struct PeopleIndex: Codable {
    var people: [String: UUID] // name -> person ID mapping
    var lastUpdated: Date
    
    init(people: [String: UUID] = [:], lastUpdated: Date = Date()) {
        self.people = people
        self.lastUpdated = lastUpdated
    }
}
