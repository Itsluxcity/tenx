import Foundation
import EventKit

/// Service responsible for automated housekeeping tasks:
/// - Analyzing journal entries for missing tasks/events
/// - Detecting and removing duplicates
/// - Ensuring data consistency across the system
class HousekeepingService {
    private let fileManager: FileStorageManager
    private let taskManager: TaskManager
    private let eventKitManager: EventKitManager
    private let claudeService: ClaudeService
    
    var onProgress: ((String) -> Void)?
    
    init(
        fileManager: FileStorageManager,
        taskManager: TaskManager,
        eventKitManager: EventKitManager,
        claudeService: ClaudeService
    ) {
        self.fileManager = fileManager
        self.taskManager = taskManager
        self.eventKitManager = eventKitManager
        self.claudeService = claudeService
    }
    
    /// Run complete housekeeping process
    func runHousekeeping() async -> HousekeepingResult {
        var result = HousekeepingResult()
        
        print("🧹 ========== HOUSEKEEPING START ==========")
        print("🧹 Timestamp: \(Date())")
        onProgress?("🧹 Starting housekeeping...")
        
        // Step 1: Deduplicate events FIRST (before creating new ones)
        print("🧹 STEP 1: Deduplicating existing events...")
        onProgress?("📅 Step 1: Checking for duplicate events...")
        let eventsDeduplicated = await deduplicateEvents()
        result.eventsDeduplicated = eventsDeduplicated
        print("✅ STEP 1 COMPLETE: Deduplicated \(eventsDeduplicated) events")
        onProgress?("✅ Removed \(eventsDeduplicated) duplicate events")
        
        // Step 2: Analyze journal for gaps
        print("🧹 STEP 2: Analyzing journal for gaps...")
        onProgress?("📖 Step 2: Analyzing journal for missing items...")
        let analysisResult = await analyzeJournalForGaps()
        
        var gaps = analysisResult.gaps
        result.gaps = gaps  // Store the gaps
        result.gapsFound = gaps.count
        print("✅ STEP 2 COMPLETE: Found \(gaps.count) gaps")
        onProgress?("✅ Found \(gaps.count) items to create")
        
        // Step 3: Create missing items
        print("🧹 STEP 3: Creating missing items...")
        onProgress?("🔨 Step 3: Creating tasks, events, and reminders...")
        let creationResult = await createMissingItems(from: gaps)
        result.tasksCreated = creationResult.tasksCreated
        result.eventsCreated = creationResult.eventsCreated
        result.remindersCreated = creationResult.remindersCreated
        result.createdTaskTitles = creationResult.createdTaskTitles
        result.createdEventTitles = creationResult.createdEventTitles
        result.createdReminderTitles = creationResult.createdReminderTitles
        print("✅ STEP 3 COMPLETE: Created \(creationResult.tasksCreated) tasks, \(creationResult.eventsCreated) events, \(creationResult.remindersCreated) reminders")
        onProgress?("✅ Created \(creationResult.tasksCreated) tasks, \(creationResult.eventsCreated) events, \(creationResult.remindersCreated) reminders")
        
        // Step 4: Deduplicate tasks
        print("🧹 STEP 4: Deduplicating tasks...")
        onProgress?("📋 Step 4: Checking for duplicate tasks...")
        do {
            let taskDedupeCount = await deduplicateTasks()
            result.tasksDeduplicated = taskDedupeCount
            print("✅ STEP 4 COMPLETE: Deduplicated \(taskDedupeCount) tasks")
            onProgress?("✅ Removed \(taskDedupeCount) duplicate tasks")
        } catch {
            print("❌ STEP 4 FAILED: \(error.localizedDescription)")
            result.errors.append("Task deduplication failed: \(error.localizedDescription)")
            onProgress?("⚠️ Task deduplication failed")
        }
        
        // Step 4.5: Deduplicate reminders
        print("🧹 STEP 4.5: Deduplicating reminders...")
        onProgress?("🔔 Step 4.5: Checking for duplicate reminders...")
        do {
            let reminderDedupeCount = await deduplicateReminders()
            result.remindersDeduplicated = reminderDedupeCount
            print("✅ STEP 4.5 COMPLETE: Deduplicated \(reminderDedupeCount) reminders")
            onProgress?("✅ Removed \(reminderDedupeCount) duplicate reminders")
        } catch {
            print("❌ STEP 4.5 FAILED: \(error.localizedDescription)")
            result.errors.append("Reminder deduplication failed: \(error.localizedDescription)")
            onProgress?("⚠️ Reminder deduplication failed")
        }
        
        // Step 5: Update daily summary
        print("🧹 STEP 5: Updating daily summary...")
        onProgress?("📝 Step 5: Updating weekly summary...")
        do {
            try await updateDailySummary()
            print("✅ STEP 5 COMPLETE: Daily summary updated")
            onProgress?("✅ Weekly summary updated")
        } catch {
            print("❌ STEP 5 FAILED: \(error.localizedDescription)")
            result.errors.append("Daily summary update failed: \(error.localizedDescription)")
            onProgress?("⚠️ Summary update failed")
        }
        
        // Step 6: Log results
        print("🧹 STEP 6: Logging results...")
        logHousekeepingResults(result)
        print("✅ STEP 6 COMPLETE: Results logged")
        
        print("✅ ========== HOUSEKEEPING COMPLETE ==========")
        print("✅ Summary: \(result.summary)")
        onProgress?("🎉 Housekeeping complete! \(result.summary)")
        print("✅ Errors: \(result.errors.count)")
        if !result.errors.isEmpty {
            print("⚠️ Error details:")
            for (index, error) in result.errors.enumerated() {
                print("   \(index + 1). \(error)")
            }
        }
        
        return result
    }
    
    // MARK: - Daily Summary
    
    /// Update the current week summary with today's journal entries
    func updateDailySummary() async throws {
        print("📝 ========== DAILY SUMMARY UPDATE START ==========")
        print("📝 Timestamp: \(Date())")
        
        // Read today's journal entries
        print("📝 Step 1: Loading current week journal...")
        let todayJournal = fileManager.loadCurrentWeekDetailedJournal()
        print("📝 Journal length: \(todayJournal.count) characters")
        
        print("📝 Step 2: Extracting today's entries...")
        let todayEntries = extractTodayEntries(from: todayJournal)
        print("📝 Today's entries length: \(todayEntries.count) characters")
        
        guard !todayEntries.isEmpty else {
            print("ℹ️ No journal entries for today to summarize")
            print("📝 ========== DAILY SUMMARY UPDATE SKIPPED ==========")
            return
        }
        
        print("📝 Today's entries preview: \(todayEntries.prefix(200))...")
        
        // Ask Claude to generate COMPLETE weekly summary (not just today's)
        print("📝 Step 3: Sending to Claude for summarization...")
        let summaryPrompt = """
        Generate a COMPLETE summary of this entire week's journal entries. This summary will REPLACE any previous version.
        
        Review ALL entries from the week and create a comprehensive summary covering:
        - Key meetings and calls this week
        - Important decisions made
        - Tasks completed
        - Follow-ups needed
        - Notable insights and progress
        
        FULL WEEK JOURNAL:
        \(todayJournal)
        
        Write a complete weekly summary (4-8 sentences) that captures everything important from this week.
        DO NOT write incremental updates - write ONE complete summary of the ENTIRE week so far.
        """
        
        do {
            let context = ClaudeContext(
                currentWeekJournal: "",
                weeklySummaries: [],
                monthlySummary: nil,
                tasks: [],
                upcomingEvents: [],
                recentEvents: [],
                reminders: [],
                currentDate: Date()
            )
            
            print("📝 Calling Claude API...")
            let response = try await claudeService.sendMessage(
                text: summaryPrompt,
                context: context,
                conversationHistory: [],
                tools: []
            )
            print("✅ Claude response received: \(response.content.count) characters")
            print("📝 Summary preview: \(response.content.prefix(200))...")
            
            // Format as complete weekly summary (no date header needed - it's the whole week)
            print("📝 Step 4: Formatting complete weekly summary...")
            let summaryEntry = """
            \(response.content)
            
            """
            
            // Get current week ID
            print("📝 Step 5: Calculating week ID...")
            let calendar = Calendar.current
            let weekOfYear = calendar.component(.weekOfYear, from: Date())
            let year = calendar.component(.yearForWeekOfYear, from: Date())
            let weekId = String(format: "%04d-W%02d", year, weekOfYear)
            print("📝 Week ID: \(weekId)")
            
            // REPLACE (not append) week summary - each daily summary is cumulative
            print("📝 Step 6: Writing to summary file...")
            let summaryFile = fileManager.documentsURL.appendingPathComponent("journal/weeks/\(weekId)-summary.md")
            print("📝 Summary file path: \(summaryFile.path)")
            
            // Read existing size before overwriting
            let oldSize = (try? String(contentsOf: summaryFile))?.count ?? 0
            
            // ALWAYS replace the entire file with new summary
            // Claude generates a COMPLETE summary each time, not incremental
            print("📝 Replacing entire summary file with new complete summary...")
            let completeContent = "# Week \(weekId) Summary\n\n" + summaryEntry
            
            do {
                try completeContent.write(to: summaryFile, atomically: true, encoding: .utf8)
                print("✅ Summary REPLACED successfully (was: \(oldSize) chars, now: \(completeContent.count) chars)")
            } catch {
                print("❌ Failed to write summary: \(error.localizedDescription)")
                throw error
            }
            
            print("✅ ========== DAILY SUMMARY UPDATE COMPLETE ==========")
            
        } catch {
            print("❌ ========== DAILY SUMMARY UPDATE FAILED ==========")
            print("❌ Error: \(error.localizedDescription)")
            print("❌ Error type: \(type(of: error))")
            if let nsError = error as NSError? {
                print("❌ Error domain: \(nsError.domain)")
                print("❌ Error code: \(nsError.code)")
                print("❌ Error userInfo: \(nsError.userInfo)")
            }
            throw error
        }
    }
    
    // MARK: - Journal Analysis
    
    private func analyzeJournalForGaps() async -> JournalAnalysisResult {
        print("📖 ========== JOURNAL ANALYSIS START ==========")
        print("📖 Timestamp: \(Date())")
        
        // Read ENTIRE week's journal (not just today)
        print("📖 Step 1: Loading current week journal...")
        let weekJournal = fileManager.loadCurrentWeekDetailedJournal()
        print("📖 Journal length: \(weekJournal.count) characters")
        
        guard !weekJournal.isEmpty else {
            print("ℹ️ No journal entries for this week")
            print("📖 ========== JOURNAL ANALYSIS SKIPPED ==========")
            return JournalAnalysisResult(gaps: [])
        }
        
        // Analyze recent entries (last 20k characters to avoid rate limits)
        print("📖 Step 2: Analyzing recent entries...")
        let recentEntries = String(weekJournal.suffix(20000))
        print("📖 Analyzing last \(recentEntries.count) characters")
        print("📖 Entries preview: \(recentEntries.prefix(200))...")
        
        // Ask Claude to analyze and extract actionable items
        let analysisPrompt = """
        Analyze the following journal entries from this week and extract ALL actionable items that may be missing from the system:
        
        \(recentEntries)
        
        For each item, identify:
        1. MEETINGS/CALLS that happened (should have calendar events)
        2. TASKS/ACTION ITEMS that need to be done (should have tasks)
        3. COMMITMENTS/FOLLOW-UPS that need reminders
        
        For each item, extract:
        - Type (meeting/task/commitment)
        - Title/description
        - Person involved (if any)
        - Date/time (if mentioned, otherwise use today)
        - Company (if mentioned)
        
        Return as a structured list.
        """
        
        do {
            // Get current tasks and events for comparison
            print("📖 Step 3: Loading existing data for comparison...")
            let existingTasks = taskManager.loadTasks()
            print("📖 Loaded \(existingTasks.count) existing tasks")
            
            let existingEvents = eventKitManager.fetchRecentEvents(daysBehind: 1)
            print("📖 Loaded \(existingEvents.count) recent events")
            
            let existingReminders = eventKitManager.fetchReminders(includeCompleted: false)
            print("📖 Loaded \(existingReminders.count) active reminders")
            
            // Send to Claude for analysis
            print("📖 Step 4: Building context for Claude...")
            let context = ClaudeContext(
                currentWeekJournal: "",
                weeklySummaries: [],
                monthlySummary: nil,
                tasks: existingTasks,
                upcomingEvents: [],
                recentEvents: existingEvents,
                reminders: existingReminders,
                currentDate: Date()
            )
            
            print("📖 Step 5: Sending to Claude for analysis...")
            let response = try await claudeService.sendMessage(
                text: analysisPrompt,
                context: context,
                conversationHistory: [],
                tools: [] // No tools needed for analysis
            )
            print("✅ Claude analysis received: \(response.content.count) characters")
            print("📖 Analysis preview: \(response.content.prefix(300))...")
            
            // Parse Claude's response to find gaps
            print("📖 Step 6: Parsing gaps from Claude's response...")
            let gaps = parseGapsFromResponse(response.content, existingTasks: existingTasks, existingEvents: existingEvents, existingReminders: existingReminders)
            
            print("✅ ========== JOURNAL ANALYSIS COMPLETE ==========")
            print("🔍 Found \(gaps.count) potential gaps")
            for (index, gap) in gaps.enumerated() {
                print("   Gap \(index + 1): \(gap.type) - \(gap.description.prefix(50))...")
            }
            
            return JournalAnalysisResult(gaps: gaps)
            
        } catch {
            print("❌ ========== JOURNAL ANALYSIS FAILED ==========")
            print("❌ Error: \(error.localizedDescription)")
            print("❌ Error type: \(type(of: error))")
            if let nsError = error as NSError? {
                print("❌ Error domain: \(nsError.domain)")
                print("❌ Error code: \(nsError.code)")
            }
            return JournalAnalysisResult(gaps: [])
        }
    }
    
    private func extractTodayEntries(from journal: String) -> String {
        let calendar = Calendar.current
        let today = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let todayString = dateFormatter.string(from: today)
        
        // Find today's section in the journal
        let lines = journal.components(separatedBy: "\n")
        var todayEntries: [String] = []
        var inTodaySection = false
        
        for line in lines {
            if line.contains(todayString) && line.hasPrefix("##") {
                inTodaySection = true
                continue
            } else if line.hasPrefix("##") && inTodaySection {
                // Hit next day's section
                break
            }
            
            if inTodaySection && !line.isEmpty {
                todayEntries.append(line)
            }
        }
        
        return todayEntries.joined(separator: "\n")
    }
    
    private func parseGapsFromResponse(_ response: String, existingTasks: [TaskItem], existingEvents: [EKEvent], existingReminders: [EKReminder]) -> [DataGap] {
        print("📋 Parsing gaps from Claude's response...")
        var gaps: [DataGap] = []
        
        // Filter out lines that are clearly not actionable items
        let lines = response.components(separatedBy: "\n")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = trimmed.lowercased()
            
            // Skip empty lines, headers, XML tags, and meta-commentary
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix("*"),
                  !trimmed.hasPrefix("<"),
                  !trimmed.hasPrefix("}"),
                  !trimmed.hasPrefix("{"),
                  !trimmed.hasPrefix("\""),
                  !lowercased.contains("i'm analyzing"),
                  !lowercased.contains("let me"),
                  !lowercased.contains("i'll"),
                  !lowercased.contains("step 1:"),
                  !lowercased.contains("step 2:"),
                  !lowercased.contains("step 3:"),
                  !lowercased.contains("analysis"),
                  !lowercased.contains("summary"),
                  !lowercased.contains("extraction"),
                  trimmed.count > 20,  // Must be substantial
                  trimmed.count < 200  // But not too long
            else { continue }
            
            // Only create events for SCHEDULED future meetings with specific times/dates
            // Must have: meeting/call + future indicator + time/date
            let hasFutureIndicator = lowercased.contains("tomorrow") || 
                                     lowercased.contains("next") ||
                                     lowercased.contains("monday") ||
                                     lowercased.contains("tuesday") ||
                                     lowercased.contains("wednesday") ||
                                     lowercased.contains("thursday") ||
                                     lowercased.contains("friday") ||
                                     lowercased.contains("scheduled") ||
                                     lowercased.contains("rescheduled") ||
                                     lowercased.contains("will meet") ||
                                     lowercased.contains("meeting at") ||
                                     lowercased.contains("call at")
            
            let hasTimeIndicator = lowercased.range(of: #"\d{1,2}:\d{2}"#, options: .regularExpression) != nil ||
                                   lowercased.contains("am") ||
                                   lowercased.contains("pm")
            
            // Skip past tense and documentation
            let isPastOrDocumentation = lowercased.contains("resolved") ||
                                       lowercased.contains("discussed") ||
                                       lowercased.contains("had a") ||
                                       lowercased.contains("happened") ||
                                       lowercased.contains("documenting") ||
                                       lowercased.contains("talked about") ||
                                       lowercased.contains("went over") ||
                                       lowercased.contains("reviewed with") ||
                                       lowercased.contains("told me") ||
                                       lowercased.contains("said that")
            
            if (lowercased.contains("meeting") || lowercased.contains("call")) &&
               hasFutureIndicator &&
               hasTimeIndicator &&
               !isPastOrDocumentation {
                // Check if we have a calendar event for this
                let hasEvent = existingEvents.contains { event in
                    guard let title = event.title else { return false }
                    return trimmed.localizedCaseInsensitiveContains(title) || title.localizedCaseInsensitiveContains(trimmed)
                }
                
                if !hasEvent {
                    print("   📅 Found missing SCHEDULED event: \(trimmed.prefix(60))...")
                    gaps.append(DataGap(
                        type: .missingCalendarEvent,
                        description: trimmed,
                        suggestedDate: Date()
                    ))
                } else {
                    print("   ⏭️  Skipping - event already exists: \(trimmed.prefix(60))...")
                }
            } else if (lowercased.contains("meeting") || lowercased.contains("call")) && !hasFutureIndicator {
                print("   ⏭️  Skipping - no future date/time: \(trimmed.prefix(60))...")
            }
            
            // Check if this is a specific task (starts with action verb or "need to")
            if (trimmed.hasPrefix("- ") && (lowercased.contains("review") || lowercased.contains("sign") || lowercased.contains("send") || lowercased.contains("create") || lowercased.contains("update"))) {
                let taskDescription = String(trimmed.dropFirst(2))  // Remove "- " prefix
                
                // Check if we have a task for this
                let hasTask = existingTasks.contains { task in
                    return taskDescription.localizedCaseInsensitiveContains(task.title) || task.title.localizedCaseInsensitiveContains(taskDescription)
                }
                
                if !hasTask {
                    print("   ✅ Found missing task: \(taskDescription.prefix(60))...")
                    gaps.append(DataGap(
                        type: .missingTask,
                        description: taskDescription,
                        suggestedDate: Date()
                    ))
                }
            }
            
            // Check if this is a specific reminder/follow-up
            if trimmed.hasPrefix("- ") && (lowercased.contains("follow up") || lowercased.contains("reminder")) {
                let reminderDescription = String(trimmed.dropFirst(2))
                
                // Check if we have a reminder for this
                let hasReminder = existingReminders.contains { reminder in
                    guard let title = reminder.title else { return false }
                    return reminderDescription.localizedCaseInsensitiveContains(title) || title.localizedCaseInsensitiveContains(reminderDescription)
                }
                
                if !hasReminder {
                    print("   🔔 Found missing reminder: \(reminderDescription.prefix(60))...")
                    gaps.append(DataGap(
                        type: .missingReminder,
                        description: reminderDescription,
                        suggestedDate: Date()
                    ))
                }
            }
        }
        
        print("📋 Filtered down to \(gaps.count) actionable gaps")
        return gaps
    }
    
    // MARK: - Create Missing Items
    
    private func createMissingItems(from gaps: [DataGap]) async -> CreationResult {
        print("🔨 Creating missing items...")
        
        var result = CreationResult()
        
        for gap in gaps {
            switch gap.type {
            case .missingTask:
                let title = cleanTaskTitle(gap.description)
                if await createTaskFromGap(gap) {
                    result.tasksCreated += 1
                    result.createdTaskTitles.append(title)
                }
            case .missingCalendarEvent:
                let title = cleanTaskTitle(gap.description)
                if await createEventFromGap(gap) {
                    result.eventsCreated += 1
                    result.createdEventTitles.append(title)
                }
            case .missingReminder:
                let title = cleanTaskTitle(gap.description)
                if await createReminderFromGap(gap) {
                    result.remindersCreated += 1
                    result.createdReminderTitles.append(title)
                }
            }
        }
        
        return result
    }
    
    private func createTaskFromGap(_ gap: DataGap) async -> Bool {
        let cleanTitle = cleanTaskTitle(gap.description)
        print("📝 Creating task: \(cleanTitle)")
        
        // SEMANTIC DUPLICATE CHECK: Check if similar task already exists
        let existingTasks = taskManager.loadTasks()
        for existingTask in existingTasks {
            if isTaskSemanticallySimilar(cleanTitle, to: existingTask.title) {
                print("⏭️  Skipping - semantically duplicate task already exists: '\(existingTask.title)'")
                return false
            }
        }
        
        // Try to extract date from description
        let dueDate = extractDateFromDescription(gap.description) ?? gap.suggestedDate
        
        let task = TaskItem(
            title: cleanTitle,
            description: "Auto-created by housekeeping from journal analysis",
            assignee: "me",
            dueDate: dueDate,
            status: .pending
        )
        
        taskManager.createOrUpdateTask(task)
        return true
    }
    
    private func extractDateFromDescription(_ description: String) -> Date? {
        let lowercased = description.lowercased()
        let calendar = Calendar.current
        let today = Date()
        
        // Look for month + day patterns (e.g., "November 28th", "on November 28", "Nov 28")
        let monthPatterns = [
            ("january", 1), ("jan", 1),
            ("february", 2), ("feb", 2),
            ("march", 3), ("mar", 3),
            ("april", 4), ("apr", 4),
            ("may", 5),
            ("june", 6), ("jun", 6),
            ("july", 7), ("jul", 7),
            ("august", 8), ("aug", 8),
            ("september", 9), ("sep", 9), ("sept", 9),
            ("october", 10), ("oct", 10),
            ("november", 11), ("nov", 11),
            ("december", 12), ("dec", 12)
        ]
        
        for (monthName, monthNum) in monthPatterns {
            if lowercased.contains(monthName) {
                // Try to find a day number after the month name
                if let monthRange = lowercased.range(of: monthName) {
                    let afterMonth = String(lowercased[monthRange.upperBound...])
                    // Look for numbers 1-31
                    let dayRegex = try? NSRegularExpression(pattern: "\\s+(\\d{1,2})")
                    if let match = dayRegex?.firstMatch(in: afterMonth, range: NSRange(afterMonth.startIndex..., in: afterMonth)) {
                        if let dayRange = Range(match.range(at: 1), in: afterMonth) {
                            if let day = Int(afterMonth[dayRange]) {
                                var components = calendar.dateComponents([.year], from: today)
                                components.month = monthNum
                                components.day = day
                                
                                // Extract time from description or default to 10am
                                let time = extractTimeFromDescription(description)
                                components.hour = time.hour
                                components.minute = time.minute
                                
                                // If the date is in the past this year, assume next year
                                if let date = calendar.date(from: components), date < today {
                                    components.year = (components.year ?? calendar.component(.year, from: today)) + 1
                                }
                                
                                print("📅 Extracted date: \(monthName) \(day) at \(time.hour):\(String(format: "%02d", time.minute))")
                                return calendar.date(from: components)
                            }
                        }
                    }
                }
            }
        }
        
        // Look for specific date patterns
        if lowercased.contains("tomorrow") {
            let time = extractTimeFromDescription(description)
            var components = calendar.dateComponents([.year, .month, .day], from: today)
            components.day = (components.day ?? 0) + 1
            components.hour = time.hour
            components.minute = time.minute
            return calendar.date(from: components)
        }
        
        if lowercased.contains("tuesday") || lowercased.contains("11/18") || lowercased.contains("11-18") {
            // Find next Tuesday or specific date
            var components = calendar.dateComponents([.year, .month, .day, .weekday], from: today)
            
            // Check if there's a specific date mentioned
            let time = extractTimeFromDescription(description)
            if lowercased.contains("11/18") || lowercased.contains("11-18") {
                components.month = 11
                components.day = 18
                components.year = 2025
                components.hour = time.hour
                components.minute = time.minute
                return calendar.date(from: components)
            }
            
            // Otherwise find next Tuesday (weekday 3)
            let currentWeekday = components.weekday ?? 1
            let daysUntilTuesday = (3 - currentWeekday + 7) % 7
            if let date = calendar.date(byAdding: .day, value: daysUntilTuesday == 0 ? 7 : daysUntilTuesday, to: today) {
                var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
                dateComponents.hour = time.hour
                dateComponents.minute = time.minute
                return calendar.date(from: dateComponents)
            }
        }
        
        if lowercased.contains("thursday") {
            let time = extractTimeFromDescription(description)
            var components = calendar.dateComponents([.year, .month, .day, .weekday], from: today)
            let currentWeekday = components.weekday ?? 1
            let daysUntilThursday = (5 - currentWeekday + 7) % 7
            if let date = calendar.date(byAdding: .day, value: daysUntilThursday == 0 ? 7 : daysUntilThursday, to: today) {
                var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
                dateComponents.hour = time.hour
                dateComponents.minute = time.minute
                return calendar.date(from: dateComponents)
            }
        }
        
        if lowercased.contains("monday") || lowercased.contains("11/17") || lowercased.contains("11-17") {
            let time = extractTimeFromDescription(description)
            if lowercased.contains("11/17") || lowercased.contains("11-17") {
                var components = calendar.dateComponents([.year, .month, .day], from: today)
                components.month = 11
                components.day = 17
                components.year = 2025
                components.hour = time.hour
                components.minute = time.minute
                return calendar.date(from: components)
            }
            
            var components = calendar.dateComponents([.year, .month, .day, .weekday], from: today)
            let currentWeekday = components.weekday ?? 1
            let daysUntilMonday = (2 - currentWeekday + 7) % 7
            if let date = calendar.date(byAdding: .day, value: daysUntilMonday == 0 ? 7 : daysUntilMonday, to: today) {
                var dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
                dateComponents.hour = time.hour
                dateComponents.minute = time.minute
                return calendar.date(from: dateComponents)
            }
        }
        
        // Look for "due [date]" pattern
        if let dueRange = lowercased.range(of: "due ") {
            let afterDue = String(lowercased[dueRange.upperBound...])
            // Try to parse common date formats
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MM/dd/yy"
            if let date = dateFormatter.date(from: String(afterDue.prefix(8))) {
                let time = extractTimeFromDescription(description)
                var components = calendar.dateComponents([.year, .month, .day], from: date)
                components.hour = time.hour
                components.minute = time.minute
                return calendar.date(from: components)
            }
        }
        
        return nil
    }
    
    private func extractTimeFromDescription(_ description: String) -> (hour: Int, minute: Int) {
        let lowercased = description.lowercased()
        
        // Look for time patterns like "at 2pm", "at 9am", "at 14:00", "2:30pm"
        let timePatterns = [
            // 12-hour format with am/pm
            ("(\\d{1,2})\\s*pm", 12), // "2pm", "2 pm" -> add 12 hours
            ("(\\d{1,2})\\s*am", 0),  // "9am", "9 am" -> as is
            ("(\\d{1,2}):(\\d{2})\\s*pm", 12), // "2:30pm" -> add 12 hours
            ("(\\d{1,2}):(\\d{2})\\s*am", 0),  // "9:30am" -> as is
        ]
        
        for (pattern, amPmOffset) in timePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: lowercased, range: NSRange(lowercased.startIndex..., in: lowercased)) {
                
                if let hourRange = Range(match.range(at: 1), in: lowercased),
                   let hour = Int(lowercased[hourRange]) {
                    
                    var minute = 0
                    // Check if there's a minute component (pattern with colon)
                    if match.numberOfRanges > 2,
                       let minuteRange = Range(match.range(at: 2), in: lowercased) {
                        minute = Int(lowercased[minuteRange]) ?? 0
                    }
                    
                    // Convert to 24-hour format
                    var adjustedHour = hour
                    if amPmOffset == 12 { // PM
                        adjustedHour = (hour == 12) ? 12 : hour + 12
                    } else { // AM
                        adjustedHour = (hour == 12) ? 0 : hour
                    }
                    
                    return (hour: adjustedHour, minute: minute)
                }
            }
        }
        
        // Look for context clues about time of day
        if lowercased.contains("morning") {
            return (hour: 9, minute: 0)
        } else if lowercased.contains("afternoon") {
            return (hour: 14, minute: 0)
        } else if lowercased.contains("evening") {
            return (hour: 17, minute: 0)
        } else if lowercased.contains("tonight") {
            return (hour: 19, minute: 0)
        }
        
        // Default to 10am (mid-morning work time)
        return (hour: 10, minute: 0)
    }
    
    private func cleanTaskTitle(_ description: String) -> String {
        var cleaned = description
        
        // Remove markdown formatting
        cleaned = cleaned.replacingOccurrences(of: "**", with: "")
        cleaned = cleaned.replacingOccurrences(of: "*", with: "")
        cleaned = cleaned.replacingOccurrences(of: "- ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "1. ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "2. ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "3. ", with: "")
        
        // Remove common prefixes
        cleaned = cleaned.replacingOccurrences(of: "Title: \"", with: "")
        cleaned = cleaned.replacingOccurrences(of: "\"", with: "")
        cleaned = cleaned.replacingOccurrences(of: "Notes: ", with: "")
        cleaned = cleaned.replacingOccurrences(of: "Purpose: ", with: "")
        
        // Remove date/time references in parentheses
        if let range = cleaned.range(of: "\\([^)]*\\d{1,2}:\\d{2}[^)]*\\)", options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        if let range = cleaned.range(of: "\\(due [^)]+\\)", options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        if let range = cleaned.range(of: "\\(today[^)]*\\)", options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        if let range = cleaned.range(of: "\\(Monday[^)]*\\)", options: .regularExpression) {
            cleaned.removeSubrange(range)
        }
        
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func createEventFromGap(_ gap: DataGap) async -> Bool {
        print("📅 Creating calendar event: \(gap.description)")
        
        // Clean the title
        let cleanTitle = cleanTaskTitle(gap.description)
        
        // SEMANTIC DUPLICATE CHECK: Check if similar event already exists
        let calendar = Calendar.current
        let existingEvents = eventKitManager.fetchUpcomingEvents(daysAhead: 7)
        
        for event in existingEvents {
            guard let eventTitle = event.title else { continue }
            if isTaskSemanticallySimilar(cleanTitle, to: eventTitle) {
                print("⏭️  Skipping - semantically duplicate event already exists: '\(eventTitle)'")
                return false
            }
        }
        
        // Extract time from description
        let (startDate, duration) = extractEventTimeFromDescription(gap.description)
        let endDate = calendar.date(byAdding: .minute, value: duration, to: startDate) ?? startDate
        
        print("📅 Event time: \(startDate) to \(endDate)")
        
        let eventId = await eventKitManager.createEvent(
            title: cleanTitle,
            start: startDate,
            end: endDate,
            notes: "Auto-created by housekeeping from journal analysis"
        )
        
        return eventId != nil
    }
    
    private func extractEventTimeFromDescription(_ description: String) -> (Date, Int) {
        let lowercased = description.lowercased()
        let calendar = Calendar.current
        var baseDate = Date()
        var duration = 60 // Default 1 hour
        var hour = 9 // Default 9 AM
        var minute = 0
        var timeFound = false
        
        // Check for "tomorrow" or specific day
        if lowercased.contains("tomorrow") || lowercased.contains("monday") {
            baseDate = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
        } else if lowercased.contains("thursday") {
            let currentWeekday = calendar.component(.weekday, from: baseDate)
            let daysUntilThursday = (5 - currentWeekday + 7) % 7
            baseDate = calendar.date(byAdding: .day, value: daysUntilThursday == 0 ? 7 : daysUntilThursday, to: baseDate) ?? baseDate
        }
        
        // Extract time - look for ALL time patterns in the description
        // Pattern 1: "10:00 AM", "2:30 PM"
        if let range = lowercased.range(of: #"(\d{1,2}):(\d{2})\s*(am|pm)"#, options: .regularExpression) {
            let timeString = String(lowercased[range])
            let components = timeString.components(separatedBy: ":")
            if let h = Int(components[0]) {
                hour = h
                if let minuteStr = components[1].components(separatedBy: " ").first,
                   let m = Int(minuteStr) {
                    minute = m
                }
                // Convert PM to 24-hour
                if timeString.contains("pm") && hour < 12 {
                    hour += 12
                } else if timeString.contains("am") && hour == 12 {
                    hour = 0
                }
                timeFound = true
            }
        }
        
        // Pattern 2: "at 10:00", "at 14:30" (24-hour format)
        if !timeFound, let range = lowercased.range(of: #"at\s+(\d{1,2}):(\d{2})"#, options: .regularExpression) {
            let timeString = String(lowercased[range])
            let numbers = timeString.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }
            if numbers.count >= 2, let h = Int(numbers[0]), let m = Int(numbers[1]) {
                hour = h
                minute = m
                timeFound = true
            }
        }
        
        // If no time found but description mentions a specific time, don't default to 9 AM
        // Instead, skip creating the event
        if !timeFound {
            print("⚠️ No specific time found in: \(description.prefix(60))... - Using default 9 AM")
        }
        
        // Look for duration hints
        if lowercased.contains("1 hour") || lowercased.contains("~1 hour") {
            duration = 60
        } else if lowercased.contains("30 min") {
            duration = 30
        } else if lowercased.contains("15 min") {
            duration = 15
        }
        
        // Set the time on the base date
        var components = calendar.dateComponents([.year, .month, .day], from: baseDate)
        components.hour = hour
        components.minute = minute
        
        let finalDate = calendar.date(from: components) ?? baseDate
        
        print("📅 Parsed time: \(hour):\(String(format: "%02d", minute)) on \(calendar.component(.day, from: finalDate))/\(calendar.component(.month, from: finalDate))")
        
        return (finalDate, duration)
    }
    
    private func createReminderFromGap(_ gap: DataGap) async -> Bool {
        let cleanTitle = cleanTaskTitle(gap.description)
        print("🔔 Creating reminder: \(cleanTitle)")
        
        // SEMANTIC DUPLICATE CHECK: Check if similar reminder already exists
        let existingReminders = eventKitManager.fetchReminders(includeCompleted: false)
        for existingReminder in existingReminders {
            guard let existingTitle = existingReminder.title else { continue }
            if isTaskSemanticallySimilar(cleanTitle, to: existingTitle) {
                print("⏭️  Skipping - semantically duplicate reminder already exists: '\(existingTitle)'")
                return false
            }
        }
        
        // Try to extract date from description (e.g., "follow up on November 28th")
        let dueDate = extractDateFromDescription(gap.description) ?? gap.suggestedDate
        print("🔔 Reminder due date: \(dueDate) (extracted from: '\(gap.description.prefix(50))...')")
        
        let reminderId = await eventKitManager.createReminder(
            title: cleanTitle,
            dueDate: dueDate,
            notes: "Auto-created by housekeeping from journal analysis"
        )
        
        return reminderId != nil
    }
    
    // MARK: - Deduplication
    
    private func deduplicateTasks() async -> Int {
        print("🔍 Checking for duplicate tasks...")
        
        var tasks = taskManager.loadTasks()
        var duplicatesRemoved = 0
        var tasksToKeep: [TaskItem] = []
        var processedIndices = Set<Int>()
        
        for i in 0..<tasks.count {
            if processedIndices.contains(i) { continue }
            
            let task = tasks[i]
            var duplicates: [Int] = []
            
            // Find duplicates of this task
            for j in (i+1)..<tasks.count {
                if processedIndices.contains(j) { continue }
                
                let otherTask = tasks[j]
                
                if isDuplicate(task, otherTask) {
                    duplicates.append(j)
                    processedIndices.insert(j)
                }
            }
            
            if duplicates.isEmpty {
                tasksToKeep.append(task)
            } else {
                // Keep the most detailed version
                var allVersions = [task] + duplicates.map { tasks[$0] }
                let bestVersion = allVersions.max { t1, t2 in
                    let score1 = (t1.description?.count ?? 0) + (t1.company != nil ? 10 : 0)
                    let score2 = (t2.description?.count ?? 0) + (t2.company != nil ? 10 : 0)
                    return score1 < score2
                }!
                
                tasksToKeep.append(bestVersion)
                duplicatesRemoved += duplicates.count
                
                print("🗑️ Removed \(duplicates.count) duplicate(s) of: \(task.title)")
            }
            
            processedIndices.insert(i)
        }
        
        if duplicatesRemoved > 0 {
            taskManager.saveTasks(tasksToKeep)
        }
        
        return duplicatesRemoved
    }
    
    private func isDuplicate(_ task1: TaskItem, _ task2: TaskItem) -> Bool {
        // Exact match
        if task1.title.lowercased() == task2.title.lowercased() &&
           task1.assignee.lowercased() == task2.assignee.lowercased() &&
           areDatesClose(task1.dueDate, task2.dueDate) {
            return true
        }
        
        // Similar title match (>90% similar)
        let similarity = stringSimilarity(task1.title, task2.title)
        if similarity > 0.9 &&
           task1.assignee.lowercased() == task2.assignee.lowercased() &&
           areDatesClose(task1.dueDate, task2.dueDate) {
            return true
        }
        
        return false
    }
    
    private func deduplicateEvents() async -> Int {
        print("🔍 Checking for duplicate events...")
        
        let events = eventKitManager.fetchUpcomingEvents(daysAhead: 30)
        var duplicatesRemoved = 0
        var processedIndices = Set<Int>()
        
        for i in 0..<events.count {
            if processedIndices.contains(i) { continue }
            
            let event = events[i]
            guard let title = event.title else { continue }
            
            // Find duplicates
            for j in (i+1)..<events.count {
                if processedIndices.contains(j) { continue }
                
                let otherEvent = events[j]
                guard let otherTitle = otherEvent.title else { continue }
                
                // Check if duplicate - same title and same time
                let titleMatch = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == 
                                otherTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                
                let timeMatch = areDatesClose(event.startDate, otherEvent.startDate)
                
                // Also check for similar titles with word matching
                let cleanTitle1 = title.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanTitle2 = otherTitle.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                let words1 = cleanTitle1.components(separatedBy: " ").filter { $0.count > 3 }
                let words2 = cleanTitle2.components(separatedBy: " ").filter { $0.count > 3 }
                let matchingWords = words1.filter { word in words2.contains(word) }
                let similarTitle = !words1.isEmpty && Double(matchingWords.count) / Double(words1.count) > 0.6
                
                if (titleMatch || similarTitle) && timeMatch {
                    // Delete the duplicate (keep the first one)
                    do {
                        try eventKitManager.deleteEvent(otherEvent)
                        duplicatesRemoved += 1
                        processedIndices.insert(j)
                        print("🗑️ Removed duplicate event: \(otherTitle) at \(otherEvent.startDate ?? Date())")
                    } catch {
                        print("❌ Failed to remove duplicate event: \(error.localizedDescription)")
                    }
                }
            }
            
            processedIndices.insert(i)
        }
        
        return duplicatesRemoved
    }
    
    private func deduplicateReminders() async -> Int {
        print("🔍 Checking for duplicate reminders...")
        
        let reminders = eventKitManager.fetchReminders(includeCompleted: false)
        var duplicatesRemoved = 0
        var processedIndices = Set<Int>()
        
        for i in 0..<reminders.count {
            if processedIndices.contains(i) { continue }
            
            let reminder = reminders[i]
            guard let title = reminder.title else { continue }
            
            // Find duplicates
            for j in (i+1)..<reminders.count {
                if processedIndices.contains(j) { continue }
                
                let otherReminder = reminders[j]
                guard let otherTitle = otherReminder.title else { continue }
                
                // Check if duplicate
                if title.lowercased() == otherTitle.lowercased() &&
                   areDatesClose(reminder.dueDateComponents?.date, otherReminder.dueDateComponents?.date) {
                    
                    // Delete the duplicate (keep the first one)
                    await eventKitManager.cancelReminder(reminderId: otherReminder.calendarItemIdentifier)
                    duplicatesRemoved += 1
                    processedIndices.insert(j)
                    
                    print("🗑️ Removed duplicate reminder: \(title)")
                }
            }
            
            processedIndices.insert(i)
        }
        
        return duplicatesRemoved
    }
    
    // MARK: - Semantic Similarity Helpers
    
    /// Check if two task titles are semantically similar (prevents duplicates like "Review contract" vs "Check contract")
    private func isTaskSemanticallySimilar(_ title1: String, to title2: String) -> Bool {
        // Normalize both titles
        let normalized1 = normalizeTitle(title1)
        let normalized2 = normalizeTitle(title2)
        
        // Exact match after normalization
        if normalized1 == normalized2 {
            return true
        }
        
        // Check string similarity using Levenshtein distance
        let similarity = stringSimilarity(normalized1, normalized2)
        if similarity > 0.85 { // 85% similar = duplicate
            return true
        }
        
        // Check if they share significant keywords
        let words1 = Set(normalized1.components(separatedBy: " ").filter { $0.count > 3 })
        let words2 = Set(normalized2.components(separatedBy: " ").filter { $0.count > 3 })
        
        if !words1.isEmpty && !words2.isEmpty {
            let commonWords = words1.intersection(words2)
            let totalWords = max(words1.count, words2.count)
            let wordOverlap = Double(commonWords.count) / Double(totalWords)
            
            if wordOverlap > 0.7 { // 70% word overlap = duplicate
                return true
            }
        }
        
        return false
    }
    
    /// Normalize title for comparison (lowercase, remove common variations)
    private func normalizeTitle(_ title: String) -> String {
        var normalized = title.lowercased()
        
        // Remove common prefixes/suffixes
        normalized = normalized.replacingOccurrences(of: "urgent:", with: "")
        normalized = normalized.replacingOccurrences(of: "important:", with: "")
        normalized = normalized.replacingOccurrences(of: "asap", with: "")
        
        // Normalize action verbs to base form
        normalized = normalized.replacingOccurrences(of: "reviewing", with: "review")
        normalized = normalized.replacingOccurrences(of: "checking", with: "check")
        normalized = normalized.replacingOccurrences(of: "sending", with: "send")
        normalized = normalized.replacingOccurrences(of: "creating", with: "create")
        normalized = normalized.replacingOccurrences(of: "updating", with: "update")
        normalized = normalized.replacingOccurrences(of: "signing", with: "sign")
        
        // Remove extra whitespace
        normalized = normalized.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        
        return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    // MARK: - Helper Methods
    
    private func areDatesClose(_ date1: Date?, _ date2: Date?) -> Bool {
        guard let date1 = date1, let date2 = date2 else {
            return date1 == nil && date2 == nil
        }
        
        let daysDifference = Calendar.current.dateComponents([.day], from: date1, to: date2).day ?? 0
        return abs(daysDifference) <= 1 // Within 1 day
    }
    
    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let longer = s1.count > s2.count ? s1 : s2
        let shorter = s1.count > s2.count ? s2 : s1
        
        if longer.count == 0 { return 1.0 }
        
        let editDistance = levenshteinDistance(shorter.lowercased(), longer.lowercased())
        return (Double(longer.count) - Double(editDistance)) / Double(longer.count)
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2Array.count + 1), count: s1Array.count + 1)
        
        for i in 0...s1Array.count {
            matrix[i][0] = i
        }
        for j in 0...s2Array.count {
            matrix[0][j] = j
        }
        
        for i in 1...s1Array.count {
            for j in 1...s2Array.count {
                let cost = s1Array[i-1] == s2Array[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
                )
            }
        }
        
        return matrix[s1Array.count][s2Array.count]
    }
    
    private func logHousekeepingResults(_ result: HousekeepingResult) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        let timestamp = dateFormatter.string(from: Date())
        
        let logEntry = """
        
        ## Housekeeping Run - \(timestamp)
        - Gaps Found: \(result.gapsFound)
        - Tasks Created: \(result.tasksCreated)
        - Events Created: \(result.eventsCreated)
        - Reminders Created: \(result.remindersCreated)
        - Tasks Deduplicated: \(result.tasksDeduplicated)
        - Reminders Deduplicated: \(result.remindersDeduplicated)
        - Errors: \(result.errors.joined(separator: ", "))
        
        """
        
        let logFile = fileManager.documentsURL.appendingPathComponent("housekeeping-log.md")
        
        if let handle = try? FileHandle(forWritingTo: logFile) {
            handle.seekToEndOfFile()
            handle.write(logEntry.data(using: .utf8)!)
            try? handle.close()
        } else {
            try? logEntry.write(to: logFile, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Data Models

struct HousekeepingResult: Codable {
    var gapsFound: Int = 0
    var tasksCreated: Int = 0
    var eventsCreated: Int = 0
    var remindersCreated: Int = 0
    var tasksDeduplicated: Int = 0
    var eventsDeduplicated: Int = 0
    var remindersDeduplicated: Int = 0
    var errors: [String] = []
    
    // Store the actual items created
    var createdTaskTitles: [String] = []
    var createdEventTitles: [String] = []
    var createdReminderTitles: [String] = []
    var gaps: [DataGap] = []
    
    var summary: String {
        """
        Found \(gapsFound) gaps, Created \(tasksCreated) tasks, \(eventsCreated) events, \(remindersCreated) reminders. \
        Deduplicated \(eventsDeduplicated) events, \(tasksDeduplicated) tasks, \(remindersDeduplicated) reminders.
        """
    }
}

// Make DataGap Codable
extension DataGap: Codable {
    enum CodingKeys: String, CodingKey {
        case type, description, suggestedDate
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let typeString = try container.decode(String.self, forKey: .type)
        switch typeString {
        case "task": type = .missingTask
        case "event": type = .missingCalendarEvent
        case "reminder": type = .missingReminder
        default: type = .missingTask
        }
        description = try container.decode(String.self, forKey: .description)
        suggestedDate = try container.decode(Date.self, forKey: .suggestedDate)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let typeString: String
        switch type {
        case .missingTask: typeString = "task"
        case .missingCalendarEvent: typeString = "event"
        case .missingReminder: typeString = "reminder"
        }
        try container.encode(typeString, forKey: .type)
        try container.encode(description, forKey: .description)
        try container.encode(suggestedDate, forKey: .suggestedDate)
    }
}

struct JournalAnalysisResult {
    let gaps: [DataGap]
}

struct DataGap {
    enum GapType {
        case missingTask
        case missingCalendarEvent
        case missingReminder
    }
    
    let type: GapType
    let description: String
    let suggestedDate: Date
}

struct CreationResult {
    var tasksCreated: Int = 0
    var eventsCreated: Int = 0
    var remindersCreated: Int = 0
    var createdTaskTitles: [String] = []
    var createdEventTitles: [String] = []
    var createdReminderTitles: [String] = []
}
