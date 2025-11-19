import Foundation

/// Multi-Agent Coordinator - Orchestrates parallel execution of specialized agents
/// Based on Anthropic's multi-agent research system architecture
class MultiAgentCoordinator {
    // MARK: - Tool Execution
    
    /// Tool executor closure - executes a single tool call and returns (attachment, result, message)
    typealias ToolExecutor = (ToolCall) async -> (MessageAttachment?, ToolResult, String)
    
    private let routerAgent: RouterAgent
    private let claudeService: ClaudeService
    private let fileManager: FileStorageManager
    private let taskManager: TaskManager
    private let eventKitManager: EventKitManager
    private let peopleManager: PeopleManager
    private var executeToolCall: ToolExecutor
    
    init(
        claudeService: ClaudeService,
        fileManager: FileStorageManager,
        taskManager: TaskManager,
        eventKitManager: EventKitManager,
        peopleManager: PeopleManager,
        executeToolCall: @escaping ToolExecutor
    ) {
        self.claudeService = claudeService
        self.fileManager = fileManager
        self.taskManager = taskManager
        self.eventKitManager = eventKitManager
        self.peopleManager = peopleManager
        self.executeToolCall = executeToolCall
        self.routerAgent = RouterAgent(claudeService: claudeService)
    }
    
    // MARK: - Configuration
    
    /// Updates the tool executor (needed because AppState can't pass self reference during init)
    func setToolExecutor(_ executor: @escaping ToolExecutor) {
        self.executeToolCall = executor
    }
    
    // MARK: - Agent Result
    
    struct AgentResult {
        let agentType: RouterAgent.AgentType
        let success: Bool
        let summary: String
        let attachments: [MessageAttachment]
        let error: String?
    }
    
    // MARK: - Multi-Agent Response
    
    struct MultiAgentResponse {
        let intent: RouterAgent.Intent
        let results: [AgentResult]
        let overallSummary: String
        let allAttachments: [MessageAttachment]
    }
    
    // MARK: - Main Coordination Function
    
    /// Handles a user request by routing to specialized agents and executing in parallel
    func handleRequest(_ userMessage: String, context: ClaudeContext, conversationHistory: [ChatMessage]) async throws -> MultiAgentResponse {
        print("📍 MultiAgentCoordinator.handleRequest() starting...")
        
        do {
            // Step 1: Router analyzes intent
            print("🧠 Router analyzing request...")
            let intent = try await routerAgent.analyzeIntent(userMessage, context: context)
            
            print("🎯 Intent detected: \(intent.actions.map { $0.rawValue }.joined(separator: ", "))")
            print("💡 Reasoning: \(intent.reasoning)")
            
            // Step 2: Spawn agents in parallel using TaskGroup
            print("🚀 Spawning \(intent.actions.count) specialized agent(s)...")
            
            let results = await withTaskGroup(of: AgentResult.self) { group in
                // Add task for each detected action
                for action in intent.actions {
                    group.addTask {
                        await self.executeAgent(
                            action,
                            userMessage: userMessage,
                            context: context,
                            intent: intent,
                            conversationHistory: conversationHistory
                        )
                    }
                }
                
                // Collect all results
                var collectedResults: [AgentResult] = []
                for await result in group {
                    collectedResults.append(result)
                }
                return collectedResults
            }
            
            // Step 3: Compile results
            print("📊 Compiling results from \(results.count) agent(s)...")
            let response = compileResults(results: results, intent: intent)
            
            print("✅ MultiAgentCoordinator.handleRequest() complete!")
            return response
            
        } catch {
            print("❌ MultiAgentCoordinator.handleRequest() FAILED!")
            print("   Error type: \(type(of: error))")
            print("   Error: \(error)")
            throw error
        }
    }
    
    // MARK: - Agent Execution
    
    /// Executes a single specialized agent
    private func executeAgent(
        _ agentType: RouterAgent.AgentType,
        userMessage: String,
        context: ClaudeContext,
        intent: RouterAgent.Intent,
        conversationHistory: [ChatMessage]
    ) async -> AgentResult {
        print("  ⚙️ \(agentType.emoji) \(agentType.name) starting...")
        let startTime = Date()
        
        do {
            let (attachments, summary) = try await runAgent(
                agentType: agentType,
                userMessage: userMessage,
                context: context,
                intent: intent,
                conversationHistory: conversationHistory
            )
            
            let duration = Date().timeIntervalSince(startTime)
            print("  ✅ \(agentType.emoji) \(agentType.name) complete (\(String(format: "%.1f", duration))s)")
            
            return AgentResult(
                agentType: agentType,
                success: true,
                summary: summary,
                attachments: attachments,
                error: nil
            )
        } catch {
            let duration = Date().timeIntervalSince(startTime)
            print("  ❌ \(agentType.emoji) \(agentType.name) failed (\(String(format: "%.1f", duration))s): \(error.localizedDescription)")
            
            return AgentResult(
                agentType: agentType,
                success: false,
                summary: "Failed to execute \(agentType.name)",
                attachments: [],
                error: error.localizedDescription
            )
        }
    }
    
    // MARK: - Specialized Agent Execution
    
    /// Runs the appropriate specialized agent based on type
    private func runAgent(
        agentType: RouterAgent.AgentType,
        userMessage: String,
        context: ClaudeContext,
        intent: RouterAgent.Intent,
        conversationHistory: [ChatMessage]
    ) async throws -> (attachments: [MessageAttachment], summary: String) {
        switch agentType {
        case .journal:
            return try await runJournalAgent(userMessage: userMessage, context: context, intent: intent, conversationHistory: conversationHistory)
        case .search:
            return try await runSearchAgent(userMessage: userMessage, context: context, intent: intent, conversationHistory: conversationHistory)
        case .task:
            return try await runTaskAgent(userMessage: userMessage, context: context, intent: intent, conversationHistory: conversationHistory)
        case .calendar:
            return try await runCalendarAgent(userMessage: userMessage, context: context, intent: intent, conversationHistory: conversationHistory)
        case .reminder:
            return try await runReminderAgent(userMessage: userMessage, context: context, intent: intent, conversationHistory: conversationHistory)
        case .people:
            return try await runPeopleAgent(userMessage: userMessage, context: context, intent: intent, conversationHistory: conversationHistory)
        }
    }
    
    // MARK: - Helper: Execute Agent Tools
    
    /// Executes tools for an agent response and returns all attachments
    private func executeAgentTools(
        response: ClaudeResponse,
        tools: [[String: Any]],
        context: ClaudeContext,
        maxLoops: Int = 5,
        conversationHistory: [ChatMessage]
    ) async throws -> (attachments: [MessageAttachment], finalResponse: String) {
        var currentResponse = response
        var allAttachments: [MessageAttachment] = []
        var mutableHistory = conversationHistory  // Make mutable copy
        var loopCount = 0
        
        while !currentResponse.toolCalls.isEmpty && loopCount < maxLoops {
            loopCount += 1
            print("    🔄 Agent loop \(loopCount), executing \(currentResponse.toolCalls.count) tool(s)")
            
            var toolResults: [ToolResult] = []
            
            for toolCall in currentResponse.toolCalls {
                print("      ⚙️ Executing: \(toolCall.name)")
                let (attachment, toolResult, _) = await executeToolCall(toolCall)
                toolResults.append(toolResult)
                
                if let attachment = attachment {
                    allAttachments.append(attachment)
                }
            }
            
            // Add assistant's tool use message to history
            let assistantContent = currentResponse.content.isEmpty ? "[Using tools]" : currentResponse.content
            mutableHistory.append(ChatMessage(role: .assistant, content: assistantContent))
            
            // Build tool results message
            var toolResultsMessage = ""
            for (index, toolCall) in currentResponse.toolCalls.enumerated() {
                let toolResult = toolResults[index]
                toolResultsMessage += "\n---\n\(toolResult.toClaudeFormat())\n"
            }
            
            mutableHistory.append(ChatMessage(role: .user, content: toolResultsMessage))
            
            // Continue conversation with tool results
            currentResponse = try await claudeService.sendMessage(
                text: "",
                context: context,
                conversationHistory: mutableHistory,
                tools: tools
            )
        }
        
        return (allAttachments, currentResponse.content)
    }
    
    // MARK: - Individual Agent Runners
    
    private func runJournalAgent(userMessage: String, context: ClaudeContext, intent: RouterAgent.Intent, conversationHistory: [ChatMessage]) async throws -> (attachments: [MessageAttachment], summary: String) {
        let agentPrompt = """
        \(JournalAgent.systemPrompt)
        
        User said: "\(userMessage)"
        Context details: \(intent.contextDetails)
        
        Log this to the journal using append_to_weekly_journal.
        """
        
        // Call Claude with Journal Agent prompt and ONLY journal tools
        let journalTools = ClaudeTools.allTools.filter { tool in
            if let name = tool["name"] as? String {
                return name == "append_to_weekly_journal"
            }
            return false
        }
        
        let response = try await claudeService.sendMessage(
            text: agentPrompt,
            context: context,
            conversationHistory: conversationHistory,
            tools: journalTools
        )
        
        // Execute tools and return results
        let (attachments, finalResponse) = try await executeAgentTools(
            response: response,
            tools: journalTools,
            context: context,
            maxLoops: 3,
            conversationHistory: conversationHistory
        )
        
        return (attachments, finalResponse)
    }
    
    private func runSearchAgent(userMessage: String, context: ClaudeContext, intent: RouterAgent.Intent, conversationHistory: [ChatMessage]) async throws -> (attachments: [MessageAttachment], summary: String) {
        let agentPrompt = """
        \(SearchAgent.systemPrompt)
        
        User asked: "\(userMessage)"
        Context details: \(intent.contextDetails)
        
        Search the journal and return the information found.
        """
        
        // Call Claude with Search Agent prompt and ONLY search tools
        let searchTools = ClaudeTools.allTools.filter { tool in
            if let name = tool["name"] as? String {
                return ["get_relevant_journal_context", "search_journal", "read_journal"].contains(name)
            }
            return false
        }
        
        let response = try await claudeService.sendMessage(
            text: agentPrompt,
            context: context,
            conversationHistory: conversationHistory,
            tools: searchTools
        )
        
        // Execute tools and return results
        let (attachments, finalResponse) = try await executeAgentTools(
            response: response,
            tools: searchTools,
            context: context,
            maxLoops: 5,
            conversationHistory: conversationHistory
        )
        
        // Return Claude's actual response as summary (this is what the user sees)
        return (attachments, finalResponse)
    }
    
    private func runTaskAgent(userMessage: String, context: ClaudeContext, intent: RouterAgent.Intent, conversationHistory: [ChatMessage]) async throws -> (attachments: [MessageAttachment], summary: String) {
        let agentPrompt = """
        \(TaskAgent.systemPrompt)
        
        User said: "\(userMessage)"
        Context details: \(intent.contextDetails)
        
        Extract actionable items and create tasks proactively.
        """
        
        // Call Claude with Task Agent prompt and ONLY task tools
        let taskTools = ClaudeTools.allTools.filter { tool in
            if let name = tool["name"] as? String {
                return ["create_or_update_task", "mark_task_complete", "delete_task"].contains(name)
            }
            return false
        }
        
        let response = try await claudeService.sendMessage(
            text: agentPrompt,
            context: context,
            conversationHistory: conversationHistory,
            tools: taskTools
        )
        
        // Execute tools and return results
        let (attachments, finalResponse) = try await executeAgentTools(
            response: response,
            tools: taskTools,
            context: context,
            maxLoops: 3,
            conversationHistory: conversationHistory
        )
        
        return (attachments, finalResponse)
    }
    
    private func runCalendarAgent(userMessage: String, context: ClaudeContext, intent: RouterAgent.Intent, conversationHistory: [ChatMessage]) async throws -> (attachments: [MessageAttachment], summary: String) {
        let agentPrompt = """
        \(CalendarAgent.systemPrompt)
        
        User said: "\(userMessage)"
        Context details: \(intent.contextDetails)
        
        Create calendar event if time is specified.
        """
        
        // Call Claude with Calendar Agent prompt and ONLY calendar tools
        let calendarTools = ClaudeTools.allTools.filter { tool in
            if let name = tool["name"] as? String {
                return ["create_calendar_event", "update_calendar_event", "delete_calendar_event"].contains(name)
            }
            return false
        }
        
        let response = try await claudeService.sendMessage(
            text: agentPrompt,
            context: context,
            conversationHistory: conversationHistory,
            tools: calendarTools
        )
        
        // Execute tools and return results
        let (attachments, finalResponse) = try await executeAgentTools(
            response: response,
            tools: calendarTools,
            context: context,
            maxLoops: 3,
            conversationHistory: conversationHistory
        )
        
        return (attachments, finalResponse)
    }
    
    private func runReminderAgent(userMessage: String, context: ClaudeContext, intent: RouterAgent.Intent, conversationHistory: [ChatMessage]) async throws -> (attachments: [MessageAttachment], summary: String) {
        let agentPrompt = """
        \(ReminderAgent.systemPrompt)
        
        User said: "\(userMessage)"
        Context details: \(intent.contextDetails)
        
        Create reminder for time-sensitive items.
        """
        
        // Call Claude with Reminder Agent prompt and ONLY reminder tools
        let reminderTools = ClaudeTools.allTools.filter { tool in
            if let name = tool["name"] as? String {
                return ["create_reminder", "update_reminder", "delete_reminder"].contains(name)
            }
            return false
        }
        
        let response = try await claudeService.sendMessage(
            text: agentPrompt,
            context: context,
            conversationHistory: conversationHistory,
            tools: reminderTools
        )
        
        // Execute tools and return results
        let (attachments, finalResponse) = try await executeAgentTools(
            response: response,
            tools: reminderTools,
            context: context,
            maxLoops: 3,
            conversationHistory: conversationHistory
        )
        
        return (attachments, finalResponse)
    }
    
    private func runPeopleAgent(userMessage: String, context: ClaudeContext, intent: RouterAgent.Intent, conversationHistory: [ChatMessage]) async throws -> (attachments: [MessageAttachment], summary: String) {
        let agentPrompt = """
        \(PeopleAgent.systemPrompt)
        
        User said: "\(userMessage)"
        Context details: \(intent.contextDetails)
        
        Log interaction with person mentioned.
        """
        
        // Call Claude with People Agent prompt and ONLY people tools
        let peopleTools = ClaudeTools.allTools.filter { tool in
            if let name = tool["name"] as? String {
                return ["read_person_file", "add_person_interaction"].contains(name)
            }
            return false
        }
        
        let response = try await claudeService.sendMessage(
            text: agentPrompt,
            context: context,
            conversationHistory: conversationHistory,
            tools: peopleTools
        )
        
        // Execute tools and return results
        let (attachments, finalResponse) = try await executeAgentTools(
            response: response,
            tools: peopleTools,
            context: context,
            maxLoops: 3,
            conversationHistory: conversationHistory
        )
        
        return (attachments, finalResponse)
    }
    
    // MARK: - Result Compilation
    
    /// Compiles results from all agents into a coherent response
    private func compileResults(results: [AgentResult], intent: RouterAgent.Intent) -> MultiAgentResponse {
        var allAttachments: [MessageAttachment] = []
        var agentResponses: [String] = []
        
        // Sort results by agent type for consistent ordering
        let sortedResults = results.sorted { $0.agentType.rawValue < $1.agentType.rawValue }
        
        for result in sortedResults {
            allAttachments.append(contentsOf: result.attachments)
            
            // Collect agent responses (the actual content from Claude)
            if result.success && !result.summary.isEmpty {
                agentResponses.append(result.summary)
            }
        }
        
        // Use agent responses as content, not summary text
        // If we have responses, use them. Otherwise use empty string (attachments will show)
        let overallSummary = agentResponses.isEmpty ? "" : agentResponses.joined(separator: "\n\n")
        
        return MultiAgentResponse(
            intent: intent,
            results: sortedResults,
            overallSummary: overallSummary,
            allAttachments: allAttachments
        )
    }
}
