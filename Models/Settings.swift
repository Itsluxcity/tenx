import Foundation

struct Settings: Codable {
    var claudeApiKey: String = "" // Add your Claude API key in the app settings
    var openAIApiKey: String = "" // Add your OpenAI API key in the app settings
    var claudeModel: ClaudeModel = .haiku35
    var autoAddToCalendar: Bool = false
    var storeRawAudio: Bool = true
    var autoResumePendingUtterances: Bool = true
    
    enum ClaudeModel: String, Codable, CaseIterable {
        case sonnet4 = "claude-sonnet-4-20250514"
        case opus4 = "claude-opus-4-20250514"
        case haiku4 = "claude-haiku-4-20250319"
        case haiku35 = "claude-3-5-haiku-20241022"
        case sonnet35 = "claude-3-5-sonnet-20241022"
        case opus3 = "claude-3-opus-20240229"
        case sonnet3 = "claude-3-sonnet-20240229"
        case haiku3 = "claude-3-haiku-20240307"
        
        var displayName: String {
            switch self {
            case .sonnet4: return "Claude Sonnet 4 ⭐️"
            case .opus4: return "Claude Opus 4"
            case .haiku4: return "Claude Haiku 4"
            case .haiku35: return "Claude 3.5 Haiku"
            case .sonnet35: return "Claude 3.5 Sonnet"
            case .opus3: return "Claude 3 Opus"
            case .sonnet3: return "Claude 3 Sonnet"
            case .haiku3: return "Claude 3 Haiku"
            }
        }
        
        var description: String {
            switch self {
            case .sonnet4: return "Latest & most capable (May 2025)"
            case .opus4: return "Most powerful reasoning (May 2025)"
            case .haiku4: return "Fast & affordable (Mar 2025)"
            case .haiku35: return "Fast with great performance"
            case .sonnet35: return "Excellent balance (Oct 2024)"
            case .opus3: return "Previous flagship"
            case .sonnet3: return "Reliable & stable"
            case .haiku3: return "Budget-friendly"
            }
        }
    }
}
