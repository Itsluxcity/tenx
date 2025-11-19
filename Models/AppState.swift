import SwiftUI
import EventKit
import UserNotifications

// MARK: - Tool Result & Validation Types

/// Structured tool result following Claude's best practices
struct ToolResult: Codable {
    let success: Bool
    let toolName: String
    let input: [String: String]
    let output: String?
    let error: String?
    let timestamp: Date
    let executionTimeMs: Int?
    
    init(success: Bool, toolName: String, input: [String: String], output: String? = nil, error: String? = nil, executionTimeMs: Int? = nil) {
        self.success = success
        self.toolName = toolName
        self.input = input
        self.output = output
        self.error = error
        self.timestamp = Date()
        self.executionTimeMs = executionTimeMs
    }
    
    func toClaudeFormat() -> String {
        var parts: [String] = []
        parts.append("Tool: \(toolName)")
        parts.append("Status: \(success ? "✅ SUCCESS" : "❌ FAILED")")
        if !input.isEmpty {
            let inputStr = input.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            parts.append("Input: \(inputStr)")
        }
        if let output = output { parts.append("Output: \(output)") }
        if let error = error { parts.append("Error: \(error)") }
        if let time = executionTimeMs { parts.append("Execution Time: \(time)ms") }
        return parts.joined(separator: "\n")
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

/// Working memory to track recent actions for undo/redo
class WorkingMemory {
    private var recentActions: [ActionRecord] = []
    private let maxActions = 10
    
    struct ActionRecord: Codable {
        let timestamp: Date
        let action: String
        let details: [String: String]
        let toolResult: ToolResult
    }
    
    func recordAction(action: String, details: [String: String], toolResult: ToolResult) {
        let record = ActionRecord(timestamp: Date(), action: action, details: details, toolResult: toolResult)
        recentActions.insert(record, at: 0)
        if recentActions.count > maxActions {
            recentActions = Array(recentActions.prefix(maxActions))
        }
        print("📝 Recorded action: \(action) - \(details)")
    }
    
    func getLastAction() -> ActionRecord? {
        return recentActions.first
    }
    
    func getActionsSummary() -> String {
        guard !recentActions.isEmpty else { return "No recent actions recorded." }
        var summary = "Recent Actions:\n"
        for (index, action) in recentActions.prefix(5).enumerated() {
            let timeAgo = Date().timeIntervalSince(action.timestamp)
            let secondsAgo = Int(timeAgo)
            summary += "\(index + 1). [\(secondsAgo)s ago] \(action.action): \(action.details.values.joined(separator: ", "))\n"
        }
        return summary
    }
}

@MainActor
class AppState: ObservableObject {
    @Published var chatSessions: [ChatSession] = []
    @Published var currentSessionId: UUID?
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var currentTranscript = ""
    @Published var tasks: [TaskItem] = []
    @Published var settings = Settings()
    @Published var currentToolProgress: [ToolProgress] = []
    
    var currentSession: ChatSession? {
        get {
            chatSessions.first(where: { $0.id == currentSessionId })
        }
        set {
            if let newValue = newValue, let index = chatSessions.firstIndex(where: { $0.id == newValue.id }) {
                chatSessions[index] = newValue
                saveSessions()
            }
        }
    }
    
    var messages: [ChatMessage] {
        currentSession?.messages ?? []
    }
    
    let audioManager = AudioManager()
    let fileManager = FileStorageManager()
    let claudeService = ClaudeService()
    let openAIService = OpenAIService()
    let eventKitManager = EventKitManager()
    let taskManager = TaskManager()
    let peopleManager: PeopleManager
    let housekeepingService: HousekeepingService
    let accountabilityService: AccountabilityService
    let workingMemory = WorkingMemory()  // Track recent actions for undo
    
    // FEATURE #6: Multi-Agent System
    let multiAgentCoordinator: MultiAgentCoordinator
    private var useMultiAgentSystem = true  // Feature flag - ENABLED! Tool execution implemented 🚀
    
    init() {
        // Initialize people manager
        self.peopleManager = PeopleManager(fileManager: fileManager)
        
        // Initialize services with dependencies
        self.housekeepingService = HousekeepingService(
            fileManager: fileManager,
            taskManager: taskManager,
            eventKitManager: eventKitManager,
            claudeService: claudeService
        )
        
        self.accountabilityService = AccountabilityService(
            taskManager: taskManager,
            fileManager: fileManager
        )
        
        // FEATURE #6: Initialize multi-agent coordinator
        // Create with placeholder executor first
        self.multiAgentCoordinator = MultiAgentCoordinator(
            claudeService: claudeService,
            fileManager: fileManager,
            taskManager: taskManager,
            eventKitManager: eventKitManager,
            peopleManager: peopleManager,
            executeToolCall: { toolCall in
                // Placeholder - will be replaced
                return (nil, ToolResult(success: false, toolName: toolCall.name, input: [:], error: "Not initialized"), "")
            }
        )
        
        loadTasks()
        loadSessions()
        if chatSessions.isEmpty {
            createNewSession()
        } else {
            currentSessionId = chatSessions.first?.id
        }
        
        // FEATURE #6: Set the real tool executor now that self is available
        multiAgentCoordinator.setToolExecutor { [weak self] toolCall in
            guard let self = self else {
                return (nil, ToolResult(success: false, toolName: toolCall.name, input: [:], error: "AppState deallocated"), "")
            }
            return await self.executeToolCallEnhanced(toolCall)
        }
        
        // Check if daily housekeeping needs to run and show morning briefing
        Task {
            await checkAndRunDailyHousekeeping()
            await showMorningBriefingIfNeeded()
        }
    }
    
    func createNewSession() {
        let newSession = ChatSession()
        chatSessions.insert(newSession, at: 0)
        currentSessionId = newSession.id
        saveSessions()
    }
    
    func deleteSession(_ session: ChatSession) {
        chatSessions.removeAll { $0.id == session.id }
        if currentSessionId == session.id {
            currentSessionId = chatSessions.first?.id
        }
        saveSessions()
    }
    
    func switchToSession(_ sessionId: UUID) {
        currentSessionId = sessionId
    }
    
    private func loadSessions() {
        let sessionsFile = fileManager.documentsURL.appendingPathComponent("chat_sessions.json")
        guard let data = try? Data(contentsOf: sessionsFile) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        chatSessions = (try? decoder.decode([ChatSession].self, from: data)) ?? []
    }
    
    private func saveSessions() {
        let sessionsFile = fileManager.documentsURL.appendingPathComponent("chat_sessions.json")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(chatSessions) {
            try? data.write(to: sessionsFile)
        }
    }
    
    func requestPermissions() async {
        // Request microphone permission
        await audioManager.requestMicrophonePermission()
        
        // Request calendar and reminders permissions
        await eventKitManager.requestCalendarAccess()
        await eventKitManager.requestRemindersAccess()
        
        // Request notification permission
        let center = UNUserNotificationCenter.current()
        try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    
    func recoverPendingUtterances() async {
        // Temporarily disabled to prevent infinite loop
        // TODO: Fix this to properly check utterance status and not reprocess completed ones
        return
        
        guard settings.autoResumePendingUtterances else { return }
        
        let pendingUtterances = fileManager.loadPendingUtterances()
        
        for utterance in pendingUtterances {
            await processUtterance(utterance, userMessageText: utterance.text)
        }
    }
    
    func startRecording() {
        isRecording = true
        recordingDuration = 0
        audioManager.startRecording()
        
        // Update recording duration timer
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }
            
            if !self.isRecording {
                timer.invalidate()
                return
            }
            
            self.recordingDuration = self.audioManager.recordingDuration
        }
    }
    
    func stopRecording() async {
        isRecording = false
        
        guard let audioURL = await audioManager.stopRecording() else {
            print("Failed to save recording")
            return
        }
        
        // Save audio file
        let savedURL = fileManager.saveAudioFile(from: audioURL)
        
        // Transcribe
        do {
            let transcript = try await openAIService.transcribe(audioURL: savedURL)
            currentTranscript = transcript
            
            // Log utterance
            let utterance = Utterance(
                sessionId: savedURL.lastPathComponent,
                text: transcript,
                status: .pending
            )
            fileManager.saveUtterance(utterance)
            
        } catch {
            print("Transcription failed: \(error)")
            // Show error to user but keep the audio file for retry
        }
    }
    
    func sendMessage(_ text: String) async {
        guard var session = currentSession else {
            createNewSession()
            guard var session = currentSession else { return }
            await sendMessage(text)
            return
        }
        
        // Check for duplicate content (last 3 messages)
        let recentMessages = session.messages.suffix(3)
        if recentMessages.contains(where: { $0.content.trimmingCharacters(in: .whitespacesAndNewlines) == text.trimmingCharacters(in: .whitespacesAndNewlines) }) {
            print("⚠️ Duplicate message detected - skipping")
            
            // Add warning message
            let warningMessage = ChatMessage(
                role: .assistant,
                content: "⚠️ I noticed you just sent the same message. I've already processed this information. Is there something specific you'd like me to do with it again?"
            )
            session.messages.append(warningMessage)
            session.updatedAt = Date()
            currentSession = session
            return
        }
        
        // Add user message to current session
        let userMessage = ChatMessage(role: .user, content: text)
        session.messages.append(userMessage)
        session.updatedAt = Date()
        
        // Update title based on conversation
        if session.messages.count == 1 {
            // First message: create a concise title
            session.title = generateChatTitle(from: text)
        } else if session.messages.count % 4 == 0 {
            // Every 4 messages, update title to reflect conversation
            let recentMessages = session.messages.suffix(6).map { $0.content }.joined(separator: " ")
            session.title = generateChatTitle(from: recentMessages)
        }
        
        currentSession = session
        
        // Clear current transcript
        currentTranscript = ""
        
        // Create utterance and mark as processing
        let utterance = Utterance(
            sessionId: UUID().uuidString,
            text: text,
            status: .processing
        )
        
        await processUtterance(utterance, userMessageText: text)
    }
    
    // MARK: - Multi-Agent Processing
    
    /// Process request using multi-agent coordinator (Feature #6)
    private func processMultiAgentRequest(userMessageText: String, context: ClaudeContext, conversationHistory: [ChatMessage]) async {
        do {
            print("🚀 Starting multi-agent coordination...")
            
            // Show initial progress indicator
            currentToolProgress = [ToolProgress(
                toolName: "🤖 Multi-Agent System",
                description: "Analyzing request and routing to specialized agents...",
                status: .inProgress,
                attachment: nil
            )]
            
            // Call multi-agent coordinator with conversation history
            let multiAgentResponse = try await multiAgentCoordinator.handleRequest(
                userMessageText,
                context: context,
                conversationHistory: conversationHistory
            )
            
            print("✅ Multi-agent response received:")
            print("   Intent: \(multiAgentResponse.intent.actions.map { $0.rawValue }.joined(separator: ", "))")
            print("   Agents executed: \(multiAgentResponse.results.count)")
            
            // Add assistant response to chat
            guard var session = currentSession else { return }
            
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: multiAgentResponse.overallSummary,
                attachments: multiAgentResponse.allAttachments
            )
            
            session.messages.append(assistantMessage)
            session.updatedAt = Date()
            currentSession = session
            
            // Clear progress indicators after message is added
            currentToolProgress = []
            
            print("💬 Multi-agent response added to chat")
            
        } catch {
            print("❌❌❌ MULTI-AGENT FAILED ❌❌❌")
            print("Error type: \(type(of: error))")
            print("Error description: \(error.localizedDescription)")
            print("Error: \(error)")
            if let claudeError = error as? ClaudeError {
                print("Claude error details: \(claudeError)")
            }
            print("🔄 FALLING BACK TO SINGLE-AGENT SYSTEM...")
            
            // Clear progress indicators
            currentToolProgress = []
            
            // Add error message to chat
            guard var session = currentSession else { return }
            let errorMessage = ChatMessage(
                role: .assistant,
                content: "⚠️ Multi-agent system encountered an error. Falling back to single-agent...\n\n(Error: \(error.localizedDescription))"
            )
            session.messages.append(errorMessage)
            session.updatedAt = Date()
            currentSession = session
            
            // ACTUALLY FALL BACK: Disable multi-agent temporarily and retry
            let originalFlag = useMultiAgentSystem
            useMultiAgentSystem = false
            
            print("🔵 Retrying with SINGLE-AGENT system...")
            await processUtterance(Utterance(sessionId: UUID().uuidString, text: userMessageText, status: .processing), userMessageText: userMessageText)
            
            // Restore flag (but maybe we should keep it disabled if it keeps failing?)
            useMultiAgentSystem = originalFlag
            print("✅ Single-agent fallback complete")
        }
    }
    
    private func processUtterance(_ utterance: Utterance, userMessageText: String) async {
        do {
            // Get context for Claude
            let context = buildContext()
            
            // Get conversation history from current session (excluding the last message we just added)
            guard let session = currentSession else { return }
            let historyWithoutCurrent = session.messages.dropLast()
            
            // FEATURE #6: Multi-Agent System (optional based on flag)
            if useMultiAgentSystem {
                print("🤖 Using MULTI-AGENT system")
                await processMultiAgentRequest(
                    userMessageText: userMessageText,
                    context: context,
                    conversationHistory: Array(historyWithoutCurrent)
                )
                return
            }
            
            // Default: Single agent flow
            print("🔵 Using SINGLE-AGENT system (legacy)")
            let response = try await claudeService.sendMessage(
                text: userMessageText,
                context: context,
                conversationHistory: Array(historyWithoutCurrent),
                tools: ClaudeTools.allTools
            )
            
            // Initialize progress tracking for all tool calls
            print("🔧 Initializing progress for \(response.toolCalls.count) tool calls")
            
            // Warn if only 1 tool call (Claude might be lazy)
            if response.toolCalls.count == 1 && response.toolCalls.first?.name == "append_to_weekly_journal" {
                print("⚠️ WARNING: Claude only called journal tool! It should also create tasks/reminders!")
            }
            
            currentToolProgress = response.toolCalls.map { toolCall in
                ToolProgress(
                    toolName: toolCall.name,
                    description: getToolDescription(toolCall),
                    status: .pending
                )
            }
            
            // Track attachments and text for the response message
            var allAttachments: [MessageAttachment] = []
            var allTextContent = response.content // Start with initial response text
            var currentResponse = response
            var conversationHistory = Array(historyWithoutCurrent)
            
            // TASK 6.3: Tool use loop with increased limit for complex searches
            var loopCount = 0
            let maxLoops = 25 // INCREASED from 10 for complex searches (was 5 originally)
            var progressTracker: [String: Int] = [:] // Track repeated tool calls
            
            while !currentResponse.toolCalls.isEmpty && loopCount < maxLoops {
                loopCount += 1
                print("🔄 Tool use loop iteration \(loopCount)")
                
                // Process tool calls and collect attachments with progress updates
                var toolResults: [ToolResult] = []
                
                for (index, toolCall) in currentResponse.toolCalls.enumerated() {
                    print("⚙️ Processing tool \(index + 1)/\(currentResponse.toolCalls.count): \(toolCall.name)")
                    
                    // TASK 6.3: Check for infinite loop patterns (repeated tool calls)
                    let argsString = toolCall.args.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
                    let toolCallSignature = "\(toolCall.name):\(argsString)"
                    progressTracker[toolCallSignature, default: 0] += 1
                    
                    if progressTracker[toolCallSignature]! > 3 {
                        print("⚠️ Detected repeated tool call (\(progressTracker[toolCallSignature]!) times): \(toolCall.name)")
                        print("💡 Suggesting Claude use notepad to track progress")
                    }
                    
                    // Update status to in_progress
                    if index < currentToolProgress.count {
                        currentToolProgress[index].status = .inProgress
                    }
                    
                    // Execute the tool with enhanced validation
                    let (attachment, toolResult, detailedMessage) = await executeToolCallEnhanced(toolCall)
                    toolResults.append(toolResult)
                    
                    // Mark as completed
                    if index < currentToolProgress.count {
                        currentToolProgress[index].status = .completed
                        currentToolProgress[index].attachment = attachment
                    }
                    
                    if let attachment = attachment {
                        print("✅ Created attachment: \(attachment.type)")
                        allAttachments.append(attachment)
                    } else {
                        print("⚠️ No attachment created for \(toolCall.name)")
                    }
                    
                    // Log validation result
                    if !toolResult.success {
                        print("⚠️ Tool validation failed: \(toolResult.error ?? "Unknown error")")
                    }
                    
                    // Small delay to show the progress
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
                
                // Send tool results back to Claude to continue
                print("📤 Sending tool results back to Claude...")
                
                // TASK 2.4: Smart conversation trimming (token-based, keeps more context)
                conversationHistory = trimConversationHistory(conversationHistory, maxTokens: 6000)
                
                // TASK 6.4: Adaptive delays based on loop count and task complexity
                if loopCount > 1 {
                    // Scale delay with task complexity (more loops = more complex = longer delays)
                    let baseDelay = 4.0  // seconds
                    let adaptiveDelay: Double
                    
                    if loopCount <= 5 {
                        adaptiveDelay = baseDelay  // 4s for first 5 loops (quick tasks)
                    } else if loopCount <= 15 {
                        adaptiveDelay = baseDelay + 2.0  // 6s for loops 6-15 (moderate tasks)
                    } else {
                        adaptiveDelay = baseDelay + 4.0  // 8s for loops 16-25 (complex searches)
                    }
                    
                    print("⏳ Waiting \(Int(adaptiveDelay))s to avoid rate limits (loop \(loopCount)/\(maxLoops))...")
                    try? await Task.sleep(nanoseconds: UInt64(adaptiveDelay * 1_000_000_000))
                }
                
                // Add assistant's tool use message to history
                // IMPORTANT: Claude API requires non-empty content, so use placeholder if empty
                let assistantContent = currentResponse.content.isEmpty ? "[Using tools]" : currentResponse.content
                conversationHistory.append(ChatMessage(
                    role: .assistant,
                    content: assistantContent
                ))
                
                // Add tool results as user messages with structured data
                var toolResultsMessage = ""
                
                // Add working memory context for undo operations
                let recentActionsContext = workingMemory.getActionsSummary()
                if !recentActionsContext.isEmpty && recentActionsContext != "No recent actions recorded." {
                    toolResultsMessage += "\n**📝 Working Memory (for undo/context):**\n\(recentActionsContext)\n"
                }
                
                for (index, toolCall) in currentResponse.toolCalls.enumerated() {
                    let toolResult = toolResults[index]
                    
                    // Add structured tool result
                    toolResultsMessage += "\n---\n\(toolResult.toClaudeFormat())\n"
                    
                    // For data-heavy tools, add the actual content
                    if toolCall.name == "read_journal" {
                        let matchingAttachment = allAttachments.first(where: { att in
                            att.title.contains("Journal Chunk")
                        })
                        
                        if let attachment = matchingAttachment, let content = attachment.actionData as? String {
                            toolResultsMessage += "\n**Content:**\n\(content)\n"
                        }
                    } else if toolCall.name == "search_journal" {
                        let matchingAttachment = allAttachments.first(where: { att in
                            att.title.contains("Search Results")
                        })
                        
                        if let attachment = matchingAttachment, let results = attachment.actionData as? String {
                            toolResultsMessage += "\n**Results:**\n\(results)\n"
                        }
                    } else if toolCall.name == "read_person_file" {
                        let personName = toolCall.args["name"] as? String ?? "Unknown"
                        let matchingAttachment = allAttachments.first(where: { att in
                            att.title.contains("Person:")
                        })
                        
                        if let attachment = matchingAttachment, let personData = attachment.actionData as? String {
                            toolResultsMessage += "\n**Person Data:**\n\(personData)\n"
                        }
                    } else if toolCall.name == "check_availability" {
                        // Critical: Send actual availability data
                        let matchingAttachment = allAttachments.first(where: { att in
                            att.title.contains("Calendar Availability")
                        })
                        
                        if let attachment = matchingAttachment, let results = attachment.actionData as? String {
                            toolResultsMessage += "\n**Availability Results:**\n\(results)\n"
                        }
                    }
                }
                
                if toolResultsMessage.isEmpty {
                    let toolNames = currentResponse.toolCalls.map { $0.name }.joined(separator: ", ")
                    toolResultsMessage = "✅ Tools executed successfully: \(toolNames). Continue with remaining tasks."
                }
                
                conversationHistory.append(ChatMessage(
                    role: .user,
                    content: toolResultsMessage
                ))
                
                // Get next response from Claude
                // Use minimal context for continuation to avoid rate limits
                let minimalContext = ClaudeContext(
                    currentWeekJournal: "", // Don't send full journal again
                    weeklySummaries: [],
                    monthlySummary: nil,
                    tasks: Array(context.tasks.prefix(5)), // Only send 5 most recent tasks
                    upcomingEvents: Array(context.upcomingEvents.prefix(3)), // Only 3 upcoming events
                    recentEvents: [], // No recent events needed for continuation
                    reminders: Array(context.reminders.prefix(3)), // Only 3 reminders
                    currentDate: context.currentDate
                )
                
                currentResponse = try await claudeService.sendMessage(
                    text: "", // Empty text, we're continuing the conversation
                    context: minimalContext,
                    conversationHistory: conversationHistory,
                    tools: ClaudeTools.allTools
                )
                
                print("📨 Claude continued with \(currentResponse.toolCalls.count) more tool calls")
                
                // If no more tools, break out of loop
                if currentResponse.toolCalls.isEmpty {
                    print("✅ Claude finished - no more tools to call")
                    break
                }
                
                // Update progress tracking for new tools
                currentToolProgress = currentResponse.toolCalls.map { toolCall in
                    ToolProgress(
                        toolName: toolCall.name,
                        description: getToolDescription(toolCall),
                        status: .pending
                    )
                }
            }
            
            if loopCount >= maxLoops {
                print("⚠️ Reached max loop count - stopping to prevent infinite loop")
            }
            
            print("📎 Total attachments: \(allAttachments.count)")
            
            // Keep progress visible longer
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            currentToolProgress = []
            
            // Add final assistant response to current session with all attachments
            let assistantMessage = ChatMessage(
                role: .assistant,
                content: currentResponse.content,
                attachments: allAttachments.isEmpty ? nil : allAttachments
            )
            
            if var session = currentSession {
                session.messages.append(assistantMessage)
                session.updatedAt = Date()
                currentSession = session
            }
            
            // Mark utterance as done
            fileManager.updateUtteranceStatus(utterance.id, status: .done)
            
        } catch {
            print("Failed to process utterance: \(error)")
            fileManager.updateUtteranceStatus(utterance.id, status: .error)
            
            // Add error message to chat
            let errorMessage = ChatMessage(
                role: .assistant,
                content: "⚠️ Error: \(error.localizedDescription)\n\nIf this is a rate limit error, please wait a moment and try again."
            )
            
            if var session = currentSession {
                session.messages.append(errorMessage)
                session.updatedAt = Date()
                currentSession = session
            }
        }
    }
    
    private func getToolDescription(_ toolCall: ToolCall) -> String {
        switch toolCall.name {
        case "create_or_update_task":
            let title = toolCall.args["title"] as? String ?? "task"
            return "Creating task: \(title)"
        case "create_calendar_event":
            let title = toolCall.args["title"] as? String ?? "event"
            return "Adding calendar event: \(title)"
        case "create_reminder":
            let title = toolCall.args["title"] as? String ?? "reminder"
            return "Setting reminder: \(title)"
        case "append_to_weekly_journal":
            return "Logging to journal"
        case "update_weekly_summary":
            return "Updating weekly summary"
        case "update_monthly_summary":
            return "Updating monthly summary"
        default:
            return "Executing \(toolCall.name)"
        }
    }
    
    // TASK 2.4: Intelligent conversation history trimming based on token estimate
    /// Trims conversation history to fit within token budget while preserving context
    /// - Parameters:
    ///   - history: The conversation history to trim
    ///   - maxTokens: Maximum tokens to keep (default 6000)
    /// - Returns: Trimmed history with first message and as many recent messages as fit
    private func trimConversationHistory(_ history: [ChatMessage], maxTokens: Int = 6000) -> [ChatMessage] {
        guard history.count > 2 else { return history }
        
        // Always keep first message (establishes context)
        let firstMessage = history.first!
        var remainingMessages = Array(history.dropFirst())
        
        // Estimate tokens (rough: 4 chars ≈ 1 token)
        func estimateTokens(_ message: ChatMessage) -> Int {
            return message.content.count / 4
        }
        
        // Keep as many recent messages as fit in budget
        var tokenCount = estimateTokens(firstMessage)
        var trimmedHistory = [firstMessage]
        
        // Work backwards from most recent
        for message in remainingMessages.reversed() {
            let messageTokens = estimateTokens(message)
            if tokenCount + messageTokens <= maxTokens {
                trimmedHistory.insert(message, at: 1) // Insert after first
                tokenCount += messageTokens
            } else {
                break
            }
        }
        
        print("📉 Trimmed conversation: kept \(trimmedHistory.count) of \(history.count) messages (~\(tokenCount) tokens)")
        return trimmedHistory
    }
    
    private func buildContext() -> ClaudeContext {
        // RATE LIMIT FIX: Minimize context size to avoid large API payloads
        // DON'T load the full journal - let Claude request it via tool if needed
        let weeklySummaries = fileManager.loadRecentWeeklySummaries(count: 1) // Just current week
        let monthlySummary = fileManager.loadCurrentMonthSummary()
        let tasksList = taskManager.loadTasks()
        
        // Fetch calendar events and reminders (heavily limited to reduce payload)
        let upcomingEvents = eventKitManager.fetchUpcomingEvents(daysAhead: 7)
        let recentEvents = eventKitManager.fetchRecentEvents(daysBehind: 1) // Just today
        let reminders = eventKitManager.fetchReminders(includeCompleted: false)
        
        return ClaudeContext(
            currentWeekJournal: "", // Empty! Claude can request via read_journal tool
            weeklySummaries: weeklySummaries,
            monthlySummary: monthlySummary,
            tasks: Array(tasksList.prefix(8)), // Only 8 most urgent tasks
            upcomingEvents: Array(upcomingEvents.prefix(3)), // Only next 3 events
            recentEvents: Array(recentEvents.prefix(2)), // Only last 2 events
            reminders: Array(reminders.prefix(3)), // Only 3 most urgent reminders
            currentDate: Date()
        )
    }
    
    /// Enhanced tool execution with structured results and validation
    /// Returns: (attachment for UI, toolResult for validation, detailedMessage for Claude)
    private func executeToolCallEnhanced(_ toolCall: ToolCall) async -> (attachment: MessageAttachment?, toolResult: ToolResult, detailedMessage: String) {
        let startTime = Date()
        let attachment = await executeToolCall(toolCall)
        let endTime = Date()
        let executionTime = Int((endTime.timeIntervalSince(startTime)) * 1000)
        
        // Create structured tool result
        let inputSummary = toolCall.args.mapValues { "\($0)" }
        var outputSummary: String? = nil
        var success = true
        var errorMessage: String? = nil
        
        // Extract output from attachment if present
        if let attachment = attachment {
            outputSummary = "\(attachment.title): \(attachment.subtitle ?? "")"
        }
        
        // Validate the result
        let validation = validateToolExecution(toolCall.name, attachment: attachment, args: toolCall.args)
        if !validation.shouldProceed {
            success = false
            errorMessage = validation.message
        }
        
        let toolResult = ToolResult(
            success: success,
            toolName: toolCall.name,
            input: inputSummary,
            output: outputSummary,
            error: errorMessage,
            executionTimeMs: executionTime
        )
        
        // Record in working memory for undo
        if success {
            recordActionInMemory(toolCall: toolCall, attachment: attachment, toolResult: toolResult)
        }
        
        // Create detailed message for Claude
        let detailedMessage = toolResult.toClaudeFormat()
        
        return (attachment, toolResult, detailedMessage)
    }
    
    private func executeToolCall(_ toolCall: ToolCall) async -> MessageAttachment? {
        switch toolCall.name {
        case "append_to_weekly_journal":
            let userContent = toolCall.args["content"] as? String ?? ""
            
            // CRITICAL: Always use CURRENT time, ignore any time Claude provides
            let now = Date()
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            let currentTime = timeFormatter.string(from: now)
            
            // Prepend current timestamp to content
            let contentWithTimestamp = "[\(currentTime)] \(userContent)"
            
            print("📝 Appending to journal: \(contentWithTimestamp.prefix(70))...")
            
            let success = fileManager.appendToWeeklyJournal(
                date: now,  // Use current date
                content: contentWithTimestamp
            )
            
            if success {
                print("✅ Appended to existing day section: ## \(DateFormatter.localizedString(from: now, dateStyle: .full, timeStyle: .none))")
            } else {
                print("❌ Failed to append to journal")
            }
            
            return nil
            
        case "delete_journal_entry":
            let date = toolCall.args["date"] as? String ?? ""
            let contentMatch = toolCall.args["content_match"] as? String ?? ""
            
            let success = fileManager.deleteJournalEntry(date: date, contentMatch: contentMatch)
            
            if success {
                print("✅ Deleted journal entry matching: \(contentMatch.prefix(50))")
            } else {
                print("❌ Could not find journal entry to delete: \(contentMatch.prefix(50))")
            }
            
            return nil
            
        case "update_weekly_summary":
            fileManager.updateWeeklySummary(
                weekId: toolCall.args["week_id"] as? String ?? "",
                summaryText: toolCall.args["summary_text"] as? String ?? "",
                appendOrReplace: toolCall.args["append_or_replace"] as? String ?? "append"
            )
            return nil
            
        case "update_monthly_summary":
            fileManager.updateMonthlySummary(
                monthId: toolCall.args["month"] as? String ?? "",
                summaryText: toolCall.args["summary_text"] as? String ?? ""
            )
            return nil
            
        case "update_yearly_summary":
            fileManager.updateYearlySummary(
                year: toolCall.args["year"] as? String ?? "",
                summaryText: toolCall.args["summary_text"] as? String ?? ""
            )
            return nil
            
        case "create_or_update_task":
            let task = TaskItem(
                title: toolCall.args["title"] as? String ?? "",
                description: toolCall.args["description"] as? String,
                company: toolCall.args["company"] as? String,
                assignee: toolCall.args["assignee"] as? String ?? "me",
                dueDate: parseDate(toolCall.args["due_date"] as? String),
                status: .pending
            )
            taskManager.createOrUpdateTask(task)
            tasks = taskManager.loadTasks()
            
            print("✅ Created task: \(task.title)")
            
            // Return task attachment
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            let dueDateStr = task.dueDate.map { dateFormatter.string(from: $0) } ?? "No due date"
            return MessageAttachment(
                type: .task,
                title: task.title,
                subtitle: "Due: \(dueDateStr) • Assignee: \(task.assignee)",
                actionData: task.id.uuidString
            )
            
        case "mark_task_complete":
            if let taskId = toolCall.args["task_id"] as? String {
                taskManager.markTaskComplete(taskId: taskId)
                tasks = taskManager.loadTasks()
            }
            return nil
            
        case "delete_task":
            let taskId = toolCall.args["task_id"] as? String
            let titleMatch = toolCall.args["title_match"] as? String
            
            var taskToDelete: TaskItem?
            
            // Try to find by ID first
            if let taskId = taskId, let uuid = UUID(uuidString: taskId) {
                taskToDelete = tasks.first { $0.id == uuid }
            }
            
            // Fall back to title match
            if taskToDelete == nil, let titleMatch = titleMatch {
                taskToDelete = tasks.first { $0.title.localizedCaseInsensitiveContains(titleMatch) }
            }
            
            if let task = taskToDelete {
                taskManager.deleteTask(taskId: task.id.uuidString)
                tasks = taskManager.loadTasks()
                print("✅ Deleted task: \(task.title)")
            } else {
                print("❌ Could not find task to delete")
            }
            
            return nil
            
        case "create_calendar_event":
            let title = toolCall.args["title"] as? String ?? ""
            let start = parseDate(toolCall.args["start"] as? String) ?? Date()
            let end = parseDate(toolCall.args["end"] as? String) ?? Date()
            let location = toolCall.args["location"] as? String
            
            // ALWAYS create calendar events
            let eventId = await eventKitManager.createEvent(
                title: title,
                start: start,
                end: end,
                location: location,
                notes: toolCall.args["notes"] as? String
            )
            
            if let eventId = eventId {
                print("✅ Created calendar event: \(title) at \(start) with ID: \(eventId)")
            } else {
                print("❌ Failed to create calendar event: \(title)")
            }
            
            // Return calendar event attachment with start date for deep link
            // Store timeIntervalSinceReferenceDate as string for calshow: URL
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            return MessageAttachment(
                type: .calendarEvent,
                title: title,
                subtitle: dateFormatter.string(from: start),
                actionData: "\(start.timeIntervalSinceReferenceDate)"
            )
            
        case "update_calendar_event":
            let eventTitle = toolCall.args["event_title"] as? String ?? ""
            let originalDate = parseDate(toolCall.args["original_date"] as? String) ?? Date()
            let newTitle = toolCall.args["new_title"] as? String
            let newStart = parseDate(toolCall.args["new_start"] as? String) ?? Date()
            let newEnd = parseDate(toolCall.args["new_end"] as? String) ?? Date()
            let newLocation = toolCall.args["new_location"] as? String
            let newNotes = toolCall.args["new_notes"] as? String
            
            let success = await eventKitManager.updateEvent(
                title: eventTitle,
                originalDate: originalDate,
                newTitle: newTitle,
                newStart: newStart,
                newEnd: newEnd,
                newLocation: newLocation,
                newNotes: newNotes
            )
            
            if success {
                print("✅ Updated calendar event: \(eventTitle) to \(newStart)")
            } else {
                print("❌ Failed to update calendar event: \(eventTitle)")
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            return MessageAttachment(
                type: .calendarEvent,
                title: newTitle ?? eventTitle,
                subtitle: "Updated to: \(dateFormatter.string(from: newStart))",
                actionData: "\(newStart.timeIntervalSinceReferenceDate)"
            )
            
        case "delete_calendar_event":
            let eventTitle = toolCall.args["event_title"] as? String ?? ""
            let eventDate = parseDate(toolCall.args["event_date"] as? String) ?? Date()
            
            let success = await eventKitManager.deleteEventByTitle(title: eventTitle, date: eventDate)
            
            if success {
                print("✅ Deleted calendar event: \(eventTitle)")
            } else {
                print("❌ Failed to delete calendar event: \(eventTitle)")
            }
            
            return nil
            
        case "check_availability":
            print("📅 RAW TOOL ARGS: \(toolCall.args)")
            let proposedTimesStrings = toolCall.args["proposed_times"] as? [String] ?? []
            let durationMinutes = toolCall.args["duration_minutes"] as? Int ?? 60
            let daysAhead = toolCall.args["days_ahead"] as? Int ?? 7
            
            print("📅 check_availability called with: \(proposedTimesStrings)")
            print("📅 Duration: \(durationMinutes) minutes, Days ahead: \(daysAhead)")
            
            // If no specific times provided, return upcoming events
            if proposedTimesStrings.isEmpty {
                print("📅 No specific times provided - returning upcoming events for next \(daysAhead) days")
                let upcomingEvents = eventKitManager.fetchUpcomingEvents(daysAhead: daysAhead)
                
                var resultText = "📅 UPCOMING EVENTS (next \(daysAhead) days):\n\n"
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "EEEE, MMM d"
                let timeFormatter = DateFormatter()
                timeFormatter.dateFormat = "h:mm a"
                
                if upcomingEvents.isEmpty {
                    resultText += "✅ No events scheduled - completely free!\n"
                } else {
                    for event in upcomingEvents {
                        let dayStr = dateFormatter.string(from: event.startDate)
                        let timeStr = "\(timeFormatter.string(from: event.startDate)) - \(timeFormatter.string(from: event.endDate))"
                        resultText += "• \(dayStr) at \(timeStr): \(event.title ?? "Untitled")\n"
                    }
                }
                
                print("📅 \(resultText)")
                
                return MessageAttachment(
                    type: .task,
                    title: "Your Calendar (\(daysAhead) days)",
                    subtitle: "\(upcomingEvents.count) events scheduled",
                    actionData: resultText
                )
            }
            
            // Parse proposed times
            let proposedTimes = proposedTimesStrings.compactMap { timeStr in
                let parsed = parseDate(timeStr)
                if parsed == nil {
                    print("❌ Failed to parse time: \(timeStr)")
                } else {
                    print("✅ Parsed time: \(timeStr) -> \(parsed!)")
                }
                return parsed
            }
            
            if proposedTimes.isEmpty {
                print("❌ No valid proposed times to check. Received: \(proposedTimesStrings)")
                print("❌ This usually means Claude sent dates in wrong format.")
                print("❌ Expected: ISO8601 like '2025-11-21T17:00:00-08:00' or '2025-11-21 17:00'")
                return nil
            }
            
            let availability = eventKitManager.checkAvailability(proposedTimes: proposedTimes, durationMinutes: durationMinutes)
            
            // Format results for Claude
            var resultText = "Availability check results:\n"
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            
            for (index, time) in proposedTimes.enumerated() {
                let timeStr = dateFormatter.string(from: time)
                let isoStr = ISO8601DateFormatter().string(from: time)
                let isFree = availability[isoStr] ?? false
                resultText += "- \(timeStr): \(isFree ? "✅ FREE" : "❌ BUSY")\n"
            }
            
            print("📅 \(resultText)")
            
            return MessageAttachment(
                type: .task,
                title: "Calendar Availability",
                subtitle: "\(availability.values.filter { $0 }.count) of \(proposedTimes.count) slots free",
                actionData: resultText
            )
            
        case "create_reminder":
            let title = toolCall.args["title"] as? String ?? ""
            let dueDate = parseDate(toolCall.args["due_date"] as? String) ?? Date()
            
            // ALWAYS create reminders and get the reminder ID
            let reminderId = await eventKitManager.createReminder(
                title: title,
                dueDate: dueDate,
                notes: toolCall.args["notes"] as? String
            )
            
            if let reminderId = reminderId {
                print("✅ Created reminder: \(title) due \(dueDate) with ID: \(reminderId)")
            } else {
                print("❌ Failed to create reminder: \(title)")
            }
            
            // Return reminder attachment with reminder ID for deep link
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            dateFormatter.timeStyle = .short
            return MessageAttachment(
                type: .reminder,
                title: title,
                subtitle: "Due: \(dateFormatter.string(from: dueDate))",
                actionData: reminderId ?? ""
            )
            
        case "restore_file_version":
            fileManager.restoreFileVersion(
                filePath: toolCall.args["file_path"] as? String ?? "",
                versionTimestamp: toolCall.args["version_timestamp"] as? String ?? ""
            )
            return nil
            
        case "read_journal":
            // Read journal in chunks to avoid rate limits
            let chunkSize = toolCall.args["chunk_size"] as? Int ?? 5000 // Default 5000 chars
            let offset = toolCall.args["offset"] as? Int ?? 0
            
            let fullJournal = fileManager.loadCurrentWeekDetailedJournal()
            let startIndex = fullJournal.index(fullJournal.startIndex, offsetBy: min(offset, fullJournal.count))
            let endIndex = fullJournal.index(startIndex, offsetBy: min(chunkSize, fullJournal.distance(from: startIndex, to: fullJournal.endIndex)))
            let chunk = String(fullJournal[startIndex..<endIndex])
            
            print("📖 Read journal chunk: offset=\(offset), size=\(chunk.count), total=\(fullJournal.count)")
            
            // Return as attachment so Claude sees the content
            return MessageAttachment(
                type: .task, // Reuse task type for display
                title: "Journal Chunk (\(offset)-\(offset + chunk.count) of \(fullJournal.count))",
                subtitle: chunk.prefix(100).description + "...",
                actionData: chunk
            )
            
        case "search_journal":
            // TASK 6.1: Enhanced search with match snippets and context
            let query = toolCall.args["query"] as? String ?? ""
            let fullJournal = fileManager.loadCurrentWeekDetailedJournal()
            let lines = fullJournal.components(separatedBy: "\n")
            
            // Find matches with surrounding context
            struct Match {
                let lineNumber: Int
                let content: String
                let context: [String]
            }
            
            var matches: [Match] = []
            for (index, line) in lines.enumerated() {
                if line.localizedCaseInsensitiveContains(query) {
                    // Get 3 lines before and 3 lines after for context
                    let contextStart = max(0, index - 3)
                    let contextEnd = min(lines.count - 1, index + 3)
                    let context = Array(lines[contextStart...contextEnd])
                    
                    matches.append(Match(
                        lineNumber: index + 1,  // 1-indexed for user
                        content: line,
                        context: context
                    ))
                }
            }
            
            // Build result with match snippets
            var result = ""
            
            if matches.isEmpty {
                result = "Found 0 matches for '\(query)' in current week's journal."
            } else {
                let limitedMatches = matches.prefix(10)
                result = "Found \(matches.count) matches for '\(query)'"
                
                if matches.count > 10 {
                    result += " (showing first 10)"
                }
                
                result += ":\n\n"
                
                for (idx, match) in limitedMatches.enumerated() {
                    result += "**Match \(idx + 1)** (Line \(match.lineNumber)):\n"
                    result += "```\n"
                    result += match.context.joined(separator: "\n")
                    result += "\n```\n\n"
                }
                
                // Calculate approximate offset for read_journal
                if let firstMatch = limitedMatches.first {
                    let estimatedCharsPerLine = 80
                    let approxOffset = max(0, (firstMatch.lineNumber - 10) * estimatedCharsPerLine)
                    result += "\n💡 Tip: Use read_journal(offset: \(approxOffset), size: 2000) to read around first match"
                }
            }
            
            print("🔍 Searched journal for '\(query)': found \(matches.count) matches, returned \(min(matches.count, 10)) with context")
            
            return MessageAttachment(
                type: .task,
                title: "Search Results for '\(query)'",
                subtitle: "\(matches.count) matches found" + (matches.count > 10 ? " (showing 10)" : ""),
                actionData: result
            )
            
        case "get_relevant_journal_context":
            // NEW: Efficient context extraction - get all relevant sections in ONE shot
            let searchQuery = toolCall.args["search_query"] as? String ?? ""
            let maxChars = toolCall.args["max_chars"] as? Int ?? 20000
            
            guard !searchQuery.isEmpty else {
                return MessageAttachment(
                    type: .task,
                    title: "No search query provided",
                    subtitle: "Please provide a search query",
                    actionData: "Error: No search query provided. Use get_relevant_journal_context(search_query: 'what to search for')"
                )
            }
            
            // Split search query into keywords
            let keywords = searchQuery.components(separatedBy: " ").filter { !$0.isEmpty }
            
            let fullJournal = fileManager.loadCurrentWeekDetailedJournal()
            let lines = fullJournal.components(separatedBy: "\n")
            
            // Find all lines matching ANY keyword
            var relevantSections: [(lineNumber: Int, contextLines: [String])] = []
            var processedRanges = Set<Int>() // Track which lines we've already included
            
            for (index, line) in lines.enumerated() {
                // Check if line contains any keyword
                let containsKeyword = keywords.contains { keyword in
                    line.localizedCaseInsensitiveContains(keyword)
                }
                
                if containsKeyword && !processedRanges.contains(index) {
                    // Extract context: 10 lines before and after
                    let contextStart = max(0, index - 10)
                    let contextEnd = min(lines.count - 1, index + 10)
                    let contextLines = Array(lines[contextStart...contextEnd])
                    
                    // Mark this range as processed
                    for i in contextStart...contextEnd {
                        processedRanges.insert(i)
                    }
                    
                    relevantSections.append((lineNumber: index + 1, contextLines: contextLines))
                }
            }
            
            // Build result with all relevant sections
            var result = ""
            
            if relevantSections.isEmpty {
                result = "No matches found for: '\(searchQuery)'"
            } else {
                result = "Found \(relevantSections.count) relevant sections for: '\(searchQuery)'\n\n"
                
                for (idx, section) in relevantSections.enumerated() {
                    result += "**Section \(idx + 1)** (around line \(section.lineNumber)):\n"
                    result += "```\n"
                    result += section.contextLines.joined(separator: "\n")
                    result += "\n```\n\n"
                    
                    // Check if we're approaching max_chars limit
                    if result.count > maxChars {
                        result += "\n[Additional sections truncated - limit reached]"
                        break
                    }
                }
                
                // Trim to max_chars if needed
                if result.count > maxChars {
                    result = String(result.prefix(maxChars)) + "\n...[truncated]"
                }
            }
            
            print("🔍 Extracted journal context: '\(searchQuery)' → \(relevantSections.count) sections, \(result.count) chars")
            
            return MessageAttachment(
                type: .task,
                title: "Journal Context: '\(searchQuery)'",
                subtitle: "\(relevantSections.count) sections, \(result.count) chars",
                actionData: result
            )
            
        case "read_person_file":
            // Read person information
            let name = toolCall.args["name"] as? String ?? ""
            
            if let person = peopleManager.loadPerson(name: name) {
                let markdown = peopleManager.exportPersonToMarkdown(person)
                print("👤 Read person file for \(name): \(person.interactions.count) interactions")
                
                return MessageAttachment(
                    type: .task,
                    title: "Person: \(name)",
                    subtitle: person.summary ?? "No summary",
                    actionData: markdown
                )
            } else {
                print("⚠️ Person not found: \(name)")
                return MessageAttachment(
                    type: .task,
                    title: "Person: \(name)",
                    subtitle: "No information found",
                    actionData: "No information available for \(name). They may not have been tracked yet."
                )
            }
            
        case "add_person_interaction":
            // Add interaction to person file
            let name = toolCall.args["name"] as? String ?? ""
            let dateStr = toolCall.args["date"] as? String ?? ""
            let time = toolCall.args["time"] as? String ?? ""
            let content = toolCall.args["content"] as? String ?? ""
            let typeStr = toolCall.args["type"] as? String ?? "note"
            
            let date = parseDate(dateStr) ?? Date()
            let type: PersonInteraction.InteractionType
            switch typeStr.lowercased() {
            case "meeting": type = .meeting
            case "call": type = .call
            case "message": type = .message
            case "email": type = .email
            default: type = .note
            }
            
            let interaction = PersonInteraction(
                date: date,
                time: time,
                content: content,
                type: type
            )
            
            peopleManager.addInteraction(to: name, interaction: interaction)
            print("👤 Added interaction for \(name): \(content.prefix(50))...")
            
            return MessageAttachment(
                type: .task,
                title: "Logged interaction with \(name)",
                subtitle: content.prefix(50).description,
                actionData: ""
            )
            
        // TASK 5.3: Notepad Tool Execution
        case "write_to_notepad":
            let content = toolCall.args["content"] as? String ?? ""
            let mode = toolCall.args["mode"] as? String ?? "append"
            
            fileManager.writeToNotepad(content, append: mode == "append")
            
            let charCount = fileManager.getNotepadSize()
            let summary = content.count > 100 ? "\(content.prefix(100))..." : content
            
            return MessageAttachment(
                type: .task,
                title: "📝 Notepad \(mode == "append" ? "Updated" : "Replaced")",
                subtitle: "Total: \(charCount) chars | \(summary)",
                actionData: "Wrote to notepad:\n\(content)"
            )
            
        case "read_notepad":
            let notepadContent = fileManager.readNotepad()
            let charCount = notepadContent.count
            
            return MessageAttachment(
                type: .task,
                title: "📖 Read Notepad",
                subtitle: "\(charCount) chars",
                actionData: notepadContent
            )
            
        case "clear_notepad":
            fileManager.clearNotepad()
            
            return MessageAttachment(
                type: .task,
                title: "🗑️ Notepad Cleared",
                subtitle: "Notepad is now empty",
                actionData: "Notepad cleared successfully"
            )
            
        default:
            print("Unknown tool: \(toolCall.name)")
            return nil
        }
    }
    
    private func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString else {
            print("⚠️ No date string provided")
            return nil
        }
        
        print("📅 Parsing date string: \(dateString)")
        
        // Try ISO8601 with options (handles with/without timezone)
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: dateString) {
            print("✅ Parsed as ISO8601 full: \(date)")
            return date
        }
        
        // Try ISO8601 without fractional seconds
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: dateString) {
            print("✅ Parsed as ISO8601: \(date)")
            return date
        }
        
        // Try ISO8601 basic formats
        iso8601Formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        if let date = iso8601Formatter.date(from: dateString) {
            print("✅ Parsed as ISO8601 basic: \(date)")
            return date
        }
        
        // Try common formats (including timezone offsets)
        let formatters = [
            "yyyy-MM-dd'T'HH:mm:ssZ",      // With timezone: 2025-11-21T17:00:00-0800
            "yyyy-MM-dd'T'HH:mm:ss",       // Without timezone: 2025-11-21T17:00:00
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",          // Short format: 2025-11-21T17:00
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd",
            "MM/dd/yyyy",
            "dd/MM/yyyy"
        ]
        
        for format in formatters {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                print("✅ Parsed with format \(format): \(date)")
                return date
            }
        }
        
        // Try relative dates
        let lowercased = dateString.lowercased()
        let calendar = Calendar.current
        let now = Date()
        
        if lowercased.contains("tomorrow") {
            let date = calendar.date(byAdding: .day, value: 1, to: now)
            print("✅ Parsed as tomorrow: \(date!)")
            return date
        }
        if lowercased.contains("today") {
            print("✅ Parsed as today: \(now)")
            return now
        }
        if lowercased.contains("next week") {
            let date = calendar.date(byAdding: .day, value: 7, to: now)
            print("✅ Parsed as next week: \(date!)")
            return date
        }
        if lowercased.contains("2 days") || lowercased.contains("two days") {
            let date = calendar.date(byAdding: .day, value: 2, to: now)
            print("✅ Parsed as 2 days: \(date!)")
            return date
        }
        
        print("❌ Failed to parse date: \(dateString)")
        return nil
    }
    
    private func loadTasks() {
        tasks = taskManager.loadTasks()
    }
    
    // MARK: - Housekeeping Functions
    
    /// Check if daily housekeeping needs to run and run it if necessary
    func checkAndRunDailyHousekeeping() async {
        print("🧹 ========== CHECK DAILY HOUSEKEEPING ==========")
        print("🧹 Timestamp: \(Date())")
        
        let lastRunKey = "last_housekeeping_run_date"
        let today = Calendar.current.startOfDay(for: Date())
        print("🧹 Today: \(today)")
        
        // Check last run date
        if let lastRunTimestamp = UserDefaults.standard.object(forKey: lastRunKey) as? Date {
            let lastRunDate = Calendar.current.startOfDay(for: lastRunTimestamp)
            print("🧹 Last run: \(lastRunDate)")
            
            if lastRunDate >= today {
                print("ℹ️ Housekeeping already ran today - SKIPPING")
                print("🧹 ========== CHECK COMPLETE (SKIPPED) ==========")
                return
            }
        } else {
            print("🧹 No previous run found - this is first run")
        }
        
        print("🧹 Running daily housekeeping...")
        let result = await housekeepingService.runHousekeeping()
        
        // Update last run date
        print("🧹 Updating last run date...")
        UserDefaults.standard.set(Date(), forKey: lastRunKey)
        print("🧹 Last run date saved: \(Date())")
        
        // Reload tasks after housekeeping
        print("🧹 Reloading tasks...")
        loadTasks()
        print("🧹 Tasks reloaded: \(tasks.count) tasks")
        
        print("✅ ========== DAILY HOUSEKEEPING COMPLETE ==========")
        print("✅ Summary: \(result.summary)")
    }
    
    /// Manually trigger housekeeping (can be called from UI)
    func runHousekeepingNow() async -> HousekeepingResult {
        print("🧹 Manual housekeeping triggered...")
        let result = await housekeepingService.runHousekeeping()
        
        // Reload tasks after housekeeping
        loadTasks()
        
        // Update last run date
        UserDefaults.standard.set(Date(), forKey: "last_housekeeping_run_date")
        
        return result
    }
    
    // MARK: - Morning Briefing & Accountability
    
    /// Show morning briefing if this is the first app open of the day
    func showMorningBriefingIfNeeded() async {
        print("☀️ ========== CHECK MORNING BRIEFING ==========")
        print("☀️ Timestamp: \(Date())")
        
        let lastBriefingKey = "last_morning_briefing_date"
        let today = Calendar.current.startOfDay(for: Date())
        print("☀️ Today: \(today)")
        
        // Only show briefing after 6am
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())
        print("☀️ Current hour: \(hour)")
        
        guard hour >= 6 else {
            print("ℹ️ Too early for morning briefing (before 6am) - SKIPPING")
            print("☀️ ========== CHECK COMPLETE (TOO EARLY) ==========")
            return
        }
        
        // Check if briefing already shown today
        if let lastBriefingTimestamp = UserDefaults.standard.object(forKey: lastBriefingKey) as? Date {
            let lastBriefingDate = Calendar.current.startOfDay(for: lastBriefingTimestamp)
            print("☀️ Last briefing: \(lastBriefingDate)")
            
            if lastBriefingDate >= today {
                print("ℹ️ Morning briefing already shown today - SKIPPING")
                print("☀️ ========== CHECK COMPLETE (ALREADY SHOWN) ==========")
                return
            }
        } else {
            print("☀️ No previous briefing found - this is first briefing")
        }
        
        print("☀️ Generating morning briefing...")
        
        // Generate briefing content
        var briefingParts: [String] = []
        
        // 1. Greeting
        briefingParts.append("☀️ Good morning! Here's your briefing for today:")
        
        // 2. Tasks due today
        let dueTodayTasks = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            let taskDueDate = Calendar.current.startOfDay(for: dueDate)
            return taskDueDate == today && task.status != .done && task.status != .cancelled
        }
        
        if !dueTodayTasks.isEmpty {
            briefingParts.append("\n**📋 Tasks Due Today (\(dueTodayTasks.count)):**")
            for task in dueTodayTasks.prefix(5) {
                briefingParts.append("- \(task.title) (Assignee: \(task.assignee))")
            }
        }
        
        // 3. Accountability check - tasks from yesterday
        let accountabilityReport = accountabilityService.checkAccountability()
        if let accountabilityPrompt = accountabilityService.generateAccountabilityPrompt(for: accountabilityReport) {
            briefingParts.append("\n**⚠️ Accountability Check:**")
            briefingParts.append(accountabilityPrompt)
        }
        
        // 4. Waiting on others
        let waitingOnTasks = accountabilityService.checkWaitingOnTasks()
        if let waitingPrompt = accountabilityService.generateWaitingOnPrompt(for: waitingOnTasks) {
            briefingParts.append("\n**⏳ Waiting On Others:**")
            briefingParts.append(waitingPrompt)
        }
        
        // 5. Today's calendar events
        let todayEvents = eventKitManager.fetchUpcomingEvents(daysAhead: 1)
        if !todayEvents.isEmpty {
            briefingParts.append("\n**📅 Today's Calendar (\(todayEvents.count) events):**")
            let dateFormatter = DateFormatter()
            dateFormatter.timeStyle = .short
            for event in todayEvents.prefix(5) {
                let timeStr = dateFormatter.string(from: event.startDate)
                briefingParts.append("- \(timeStr): \(event.title ?? "Untitled")")
            }
        }
        
        // Only show briefing if there's something to say
        print("☀️ Briefing parts count: \(briefingParts.count)")
        guard briefingParts.count > 1 else {
            print("ℹ️ Nothing to brief about today - SKIPPING")
            print("☀️ ========== MORNING BRIEFING SKIPPED (NOTHING TO SAY) ==========")
            return
        }
        
        print("☀️ Creating briefing message...")
        print("☀️ Briefing content preview: \(briefingParts.joined(separator: "\n").prefix(300))...")
        
        // Add briefing as assistant message
        let briefingMessage = ChatMessage(
            role: .assistant,
            content: briefingParts.joined(separator: "\n")
        )
        
        print("☀️ Adding briefing to current session...")
        if var session = currentSession {
            print("☀️ Current session ID: \(session.id)")
            print("☀️ Current session messages count: \(session.messages.count)")
            
            session.messages.append(briefingMessage)
            session.updatedAt = Date()
            currentSession = session
            
            print("✅ Briefing message added to session")
            print("☀️ New messages count: \(session.messages.count)")
        } else {
            print("❌ No current session found - briefing not added")
        }
        
        // Mark briefing as shown
        print("☀️ Marking briefing as shown...")
        UserDefaults.standard.set(Date(), forKey: lastBriefingKey)
        print("☀️ Briefing date saved: \(Date())")
        
        print("✅ ========== MORNING BRIEFING COMPLETE ==========")
    }
    
    // MARK: - Chat Title Generation
    
    private func generateChatTitle(from text: String) -> String {
        // Extract key topics and people from the message
        var title = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common question patterns
        title = title.replacingOccurrences(of: "What do you know about ", with: "", options: .caseInsensitive)
        title = title.replacingOccurrences(of: "Tell me about ", with: "", options: .caseInsensitive)
        title = title.replacingOccurrences(of: "Can you ", with: "", options: .caseInsensitive)
        title = title.replacingOccurrences(of: "Could you ", with: "", options: .caseInsensitive)
        title = title.replacingOccurrences(of: "Please ", with: "", options: .caseInsensitive)
        title = title.replacingOccurrences(of: "?", with: "")
        
        // If it mentions specific people, focus on them
        let peopleNames = peopleManager.loadAllPeople().map { $0.name }
        let mentionedPeople = peopleNames.filter { title.localizedCaseInsensitiveContains($0) }
        
        if !mentionedPeople.isEmpty {
            if mentionedPeople.count == 1 {
                title = mentionedPeople[0]
            } else if mentionedPeople.count == 2 {
                title = "\(mentionedPeople[0]) & \(mentionedPeople[1])"
            } else {
                title = "\(mentionedPeople[0]) & \(mentionedPeople.count - 1) others"
            }
        }
        
        // Capitalize first letter
        if !title.isEmpty {
            title = title.prefix(1).uppercased() + title.dropFirst()
        }
        
        // Limit length
        if title.count > 40 {
            title = String(title.prefix(37)) + "..."
        }
        
        return title.isEmpty ? "New Chat" : title
    }
    
    // MARK: - Tool Validation & Memory
    
    private func validateToolExecution(_ toolName: String, attachment: MessageAttachment?, args: [String: Any]) -> ValidationResult {
        switch toolName {
        case "check_availability":
            // Critical: This tool must return actual data
            if attachment == nil {
                return .failed(error: "check_availability returned no data. Proposed times may be invalid or calendar access failed.")
            }
            if let actionData = attachment?.actionData, actionData.contains("0 of") {
                return .retry(reason: "All proposed times failed to parse", suggestion: "Check date format - must be ISO8601 like '2025-11-21T17:00:00-08:00'")
            }
            return .proceed(message: "✅ Availability check completed successfully")
            
        case "update_calendar_event":
            // Check if event was actually found and modified
            if attachment == nil {
                return .retry(reason: "Event not found in calendar", suggestion: "Try searching with a different title or date range")
            }
            return .proceed(message: "✅ Calendar event updated successfully")
            
        case "delete_calendar_event":
            // Delete operations return nil attachment by design (nothing to show after deletion)
            // Success/failure is logged in console, validation always proceeds
            return .proceed(message: "✅ Calendar event deletion executed")
            
        case "delete_journal_entry", "delete_task":
            // For delete operations, nil attachment might mean success (nothing to show)
            // We rely on console logs to verify
            return .proceed(message: "✅ Delete operation executed")
            
        case "create_calendar_event", "create_reminder", "create_or_update_task":
            // Creation should always return an attachment for the user
            if attachment == nil {
                return .failed(error: "Creation failed - no confirmation returned")
            }
            return .proceed(message: "✅ Item created successfully")
            
        case "read_person_file", "search_journal", "read_journal":
            // Read operations should return data
            if attachment == nil {
                return .failed(error: "Read operation returned no data")
            }
            return .proceed(message: "✅ Data retrieved successfully")
            
        default:
            // Default: assume success unless attachment was expected but missing
            return .proceed(message: "✅ Tool executed")
        }
    }
    
    private func recordActionInMemory(toolCall: ToolCall, attachment: MessageAttachment?, toolResult: ToolResult) {
        var action = toolCall.name
        var details: [String: String] = [:]
        
        switch toolCall.name {
        case "create_calendar_event":
            action = "created_event"
            details["title"] = toolCall.args["title"] as? String ?? "Unknown"
            details["date"] = toolCall.args["start"] as? String ?? ""
            
        case "append_to_weekly_journal":
            action = "added_journal"
            details["content"] = (toolCall.args["content"] as? String ?? "").prefix(50).description
            details["time"] = toolCall.args["time"] as? String ?? ""
            
        case "create_or_update_task":
            action = "created_task"
            details["title"] = toolCall.args["title"] as? String ?? "Unknown"
            details["assignee"] = toolCall.args["assignee"] as? String ?? ""
            
        case "update_calendar_event":
            action = "updated_event"
            details["title"] = toolCall.args["event_title"] as? String ?? "Unknown"
            details["new_date"] = toolCall.args["new_start"] as? String ?? ""
            
        case "delete_calendar_event":
            action = "deleted_event"
            details["title"] = toolCall.args["event_title"] as? String ?? "Unknown"
            
        case "delete_journal_entry":
            action = "deleted_journal"
            details["content_match"] = (toolCall.args["content_match"] as? String ?? "").prefix(30).description
            
        case "delete_task":
            action = "deleted_task"
            details["title"] = toolCall.args["title_match"] as? String ?? (toolCall.args["task_id"] as? String ?? "Unknown")
            
        default:
            details["tool"] = toolCall.name
        }
        
        workingMemory.recordAction(action: action, details: details, toolResult: toolResult)
    }
}
