import Foundation

/// Structured tool result following Claude's best practices
/// Provides detailed execution information for verification and retry logic
struct ToolResult: Codable {
    let success: Bool
    let toolName: String
    let input: [String: String]  // Simplified for JSON encoding
    let output: String?
    let error: String?
    let timestamp: Date
    let executionTimeMs: Int?
    
    init(
        success: Bool,
        toolName: String,
        input: [String: String],
        output: String? = nil,
        error: String? = nil,
        executionTimeMs: Int? = nil
    ) {
        self.success = success
        self.toolName = toolName
        self.input = input
        self.output = output
        self.error = error
        self.timestamp = Date()
        self.executionTimeMs = executionTimeMs
    }
    
    /// Format for sending back to Claude
    func toClaudeFormat() -> String {
        var parts: [String] = []
        
        parts.append("Tool: \(toolName)")
        parts.append("Status: \(success ? "✅ SUCCESS" : "❌ FAILED")")
        
        if !input.isEmpty {
            let inputStr = input.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            parts.append("Input: \(inputStr)")
        }
        
        if let output = output {
            parts.append("Output: \(output)")
        }
        
        if let error = error {
            parts.append("Error: \(error)")
        }
        
        if let time = executionTimeMs {
            parts.append("Execution Time: \(time)ms")
        }
        
        return parts.joined(separator: "\n")
    }
}

/// Working memory to track recent actions for undo/redo
class WorkingMemory {
    private var recentActions: [ActionRecord] = []
    private let maxActions = 10
    
    struct ActionRecord: Codable {
        let timestamp: Date
        let action: String  // "created_event", "added_journal", "created_task"
        let details: [String: String]  // {"title": "Nick call", "date": "2025-11-21"}
        let toolResult: ToolResult
    }
    
    func recordAction(action: String, details: [String: String], toolResult: ToolResult) {
        let record = ActionRecord(
            timestamp: Date(),
            action: action,
            details: details,
            toolResult: toolResult
        )
        
        recentActions.insert(record, at: 0)
        
        // Keep only last N actions
        if recentActions.count > maxActions {
            recentActions = Array(recentActions.prefix(maxActions))
        }
        
        print("📝 Recorded action: \(action) - \(details)")
    }
    
    func getLastAction() -> ActionRecord? {
        return recentActions.first
    }
    
    func getLastNActions(_ n: Int) -> [ActionRecord] {
        return Array(recentActions.prefix(n))
    }
    
    func getActionsSummary() -> String {
        guard !recentActions.isEmpty else {
            return "No recent actions recorded."
        }
        
        var summary = "Recent Actions:\n"
        for (index, action) in recentActions.prefix(5).enumerated() {
            let timeAgo = Date().timeIntervalSince(action.timestamp)
            let secondsAgo = Int(timeAgo)
            summary += "\(index + 1). [\(secondsAgo)s ago] \(action.action): \(action.details.values.joined(separator: ", "))\n"
        }
        
        return summary
    }
    
    func clearHistory() {
        recentActions.removeAll()
    }
}

/// Validation result for tool execution
enum ValidationResult {
    case proceed(message: String)
    case retry(reason: String, suggestion: String)
    case failed(error: String)
    
    var shouldProceed: Bool {
        switch self {
        case .proceed: return true
        default: return false
        }
    }
    
    var message: String {
        switch self {
        case .proceed(let msg): return msg
        case .retry(let reason, let suggestion): return "⚠️ \(reason). Suggestion: \(suggestion)"
        case .failed(let error): return "❌ \(error)"
        }
    }
}
