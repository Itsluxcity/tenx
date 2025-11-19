import Foundation

/// Router Agent - Analyzes user intent and determines which specialized agents to spawn
/// Based on Anthropic's multi-agent research system architecture
class RouterAgent {
    private let claudeService: ClaudeService
    
    init(claudeService: ClaudeService) {
        self.claudeService = claudeService
    }
    
    // MARK: - Agent Types
    
    enum AgentType: String, Codable {
        case journal = "JOURNAL"
        case search = "SEARCH"
        case task = "TASK"
        case calendar = "CALENDAR"
        case reminder = "REMINDER"
        case people = "PEOPLE"
        
        var emoji: String {
            switch self {
            case .journal: return "📝"
            case .search: return "🔍"
            case .task: return "✅"
            case .calendar: return "📅"
            case .reminder: return "🔔"
            case .people: return "👤"
            }
        }
        
        var name: String {
            switch self {
            case .journal: return "Journal Agent"
            case .search: return "Search Agent"
            case .task: return "Task Agent"
            case .calendar: return "Calendar Agent"
            case .reminder: return "Reminder Agent"
            case .people: return "People Agent"
            }
        }
    }
    
    // MARK: - Intent Structure
    
    struct Intent: Codable {
        let actions: [AgentType]
        let reasoning: String
        let contextDetails: String
        
        enum CodingKeys: String, CodingKey {
            case actions
            case reasoning
            case contextDetails = "context_details"
        }
    }
    
    // MARK: - Intent Analysis
    
    /// Analyzes user message and determines which agents should be activated
    /// Uses lightweight Sonnet 4 call for fast classification
    func analyzeIntent(_ userMessage: String, context: ClaudeContext) async throws -> Intent {
        print("🧠 Router analyzing message: \"\(userMessage.prefix(50))...\"")
        
        do {
            let analysisPrompt = buildAnalysisPrompt(userMessage: userMessage)
            print("📝 Router prompt built (\(analysisPrompt.count) chars)")
            
            // Make lightweight API call (no tools, just classification)
            print("📡 Calling Claude API for intent analysis...")
            let response = try await claudeService.sendMessage(
                text: analysisPrompt,
                context: context,
                conversationHistory: [],
                tools: [] // Router doesn't need tools
            )
            
            print("📨 Router received response (\(response.content.count) chars)")
            print("📄 Response content: \(response.content)")
            
            // Parse JSON response
            print("🔍 Parsing intent from response...")
            let intent = try parseIntentFromResponse(response.content)
            
            print("🎯 Intent detected: \(intent.actions.map { $0.rawValue }.joined(separator: ", "))")
            print("💡 Reasoning: \(intent.reasoning)")
            
            return intent
        } catch {
            print("❌ Router analyzeIntent failed!")
            print("   Error type: \(type(of: error))")
            print("   Error: \(error)")
            throw error
        }
    }
    
    // MARK: - Private Methods
    
    private func buildAnalysisPrompt(userMessage: String) -> String {
        return """
        Analyze this user message and determine what actions are needed.
        
        User message: "\(userMessage)"
        
        Classify into one or more actions:
        - JOURNAL: Log an event/update to journal
        - SEARCH: Find information in journal
        - TASK: Create/update/complete a task
        - CALENDAR: Create/update calendar event (scheduled meetings with specific times)
        - REMINDER: Create time-based reminder/alert
        - PEOPLE: Update person's interaction file
        
        🎯 **CRITICAL: BE PROACTIVE - DON'T WAIT TO BE ASKED!**
        
        The user should NOT have to say "remind me" or "create a task" for you to do it.
        Extract actionable items automatically and intelligently!
        
        **BIAS RULES (How aggressive to be with each type):**
        
        1. **TASK - VERY AGGRESSIVE (70% bias)**
           - ANY commitment mentioned = TASK
           - ANY future action item = TASK
           - ANY "will do", "need to", "should", "going to" = TASK
           - Someone else's action = TASK for them
           - Even vague future intentions = TASK
           
           Examples that should trigger TASK:
           ✅ "Scott is going to consolidate expenses" → Create task
           ✅ "I need to follow up with Sarah" → Create task
           ✅ "Tommy's sending the breakdown" → Create task (for Tommy)
           ✅ "Should review the contract" → Create task
           ✅ "Need to check in next week" → Create task
        
        2. **CALENDAR - CONSERVATIVE (20% bias)**
           - ONLY for scheduled meetings/calls with SPECIFIC times
           - Must have time/date explicitly mentioned
           - Don't create calendar events for vague future items
           
           When to use CALENDAR:
           ✅ "Meeting with Scott tomorrow at 3pm" → Calendar event
           ✅ "Call with Nick scheduled for Thursday 2pm" → Calendar event
           ❌ "Need to meet with Tommy" → NO (use TASK instead)
           ❌ "Follow up next week" → NO (use TASK instead)
        
        3. **REMINDER - MODERATE (50% bias)**
           - Use for important time-sensitive items
           - Use when specific deadlines mentioned
           - Use when urgency implied
           
           When to use REMINDER:
           ✅ "Contract due by Friday" → Reminder + Task
           ✅ "Don't forget to call Sarah" → Reminder + Task
           ✅ "Deadline tomorrow" → Reminder + Task
           ✅ User explicitly says "remind me" → Reminder
           ❌ General future item → NO (just TASK)
        
        **CLASSIFICATION RULES:**
        - Past tense ("had meeting", "talked with", "just finished") = JOURNAL + PEOPLE (if person mentioned)
        - Present/ongoing ("I'm working on", "currently") = JOURNAL
        - Question ("what did", "find", "search for") = SEARCH
        - Future action ("will", "need to", "going to", "should") = TASK (always!)
        - Scheduled meeting with time = CALENDAR + TASK
        - Person mentioned = PEOPLE (if interaction happened)
        - Commitment made by someone = TASK (for that person)
        - Deadline mentioned = TASK + REMINDER
        - Multiple actions can apply simultaneously!
        
        **EXAMPLES:**
        
        "I just had a meeting with Scott about Ring LLC. He's going to consolidate expenses by Friday."
        → JOURNAL (log meeting) 
          + PEOPLE (update Scott) 
          + TASK (Scott to consolidate expenses - due Friday)
          + REMINDER (remind about Friday deadline)
        
        "Find what Tommy said about merch"
        → SEARCH (find info)
        
        "I finished the report. Need to send it to Sarah."
        → JOURNAL (log completion) 
          + TASK (send report to Sarah)
        
        "Call with Nick went well. He's sending the contract tomorrow."
        → JOURNAL (log call)
          + PEOPLE (update Nick)
          + TASK (Nick to send contract - due tomorrow)
          + REMINDER (expect contract tomorrow)
        
        "Meeting with Tommy next Tuesday at 2pm to discuss merch"
        → JOURNAL (log that meeting was scheduled)
          + TASK (prepare for Tommy meeting)
          + CALENDAR (Meeting with Tommy - Tue 2pm)
        
        "Should follow up with Sarah about the proposal"
        → TASK (follow up with Sarah about proposal)
        
        "Talked with Nick. Need to review his ideas."
        → JOURNAL (log conversation)
          + PEOPLE (update Nick)
          + TASK (review Nick's ideas)
        
        **IMPORTANT**: Respond ONLY with valid JSON in this exact format:
        {
          "actions": ["JOURNAL", "PEOPLE", "TASK", "REMINDER"],
          "reasoning": "Past tense meeting + person mentioned + future commitment with deadline",
          "context_details": "Meeting with Scott about Ring LLC - he will consolidate expenses by Friday"
        }
        
        Do not include any other text, explanations, or markdown. Just the JSON object.
        """
    }
    
    private func parseIntentFromResponse(_ response: String) throws -> Intent {
        // Extract JSON from response (might be wrapped in markdown or other text)
        var jsonString = response.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove markdown code blocks if present
        if jsonString.hasPrefix("```json") {
            jsonString = jsonString.replacingOccurrences(of: "```json", with: "")
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if jsonString.hasPrefix("```") {
            jsonString = jsonString.replacingOccurrences(of: "```", with: "")
            jsonString = jsonString.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Try to find JSON object if wrapped in other text
        if let startRange = jsonString.range(of: "{"),
           let endRange = jsonString.range(of: "}", options: .backwards) {
            let start = startRange.lowerBound
            let end = jsonString.index(after: endRange.lowerBound)
            jsonString = String(jsonString[start..<end])
        }
        
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("❌ Failed to convert response to data")
            print("Response was: \(response)")
            throw RouterError.invalidJSON("Could not convert response to data")
        }
        
        do {
            let intent = try JSONDecoder().decode(Intent.self, from: jsonData)
            return intent
        } catch {
            print("❌ Failed to decode JSON: \(error)")
            print("JSON was: \(jsonString)")
            throw RouterError.invalidJSON("Failed to decode: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum RouterError: Error {
    case invalidJSON(String)
    case noActionsDetected
    
    var localizedDescription: String {
        switch self {
        case .invalidJSON(let details):
            return "Invalid JSON response from router: \(details)"
        case .noActionsDetected:
            return "Router could not detect any actions from user message"
        }
    }
}
