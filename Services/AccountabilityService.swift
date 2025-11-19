import Foundation

/// Service responsible for proactive accountability:
/// - Checking for incomplete tasks
/// - Identifying tasks user didn't mention completing
/// - Generating accountability prompts
class AccountabilityService {
    private let taskManager: TaskManager
    private let fileManager: FileStorageManager
    
    init(taskManager: TaskManager, fileManager: FileStorageManager) {
        self.taskManager = taskManager
        self.fileManager = fileManager
    }
    
    /// Check for tasks that were due today but user didn't mention completing
    func checkAccountability() -> AccountabilityReport {
        print("🔍 ========== ACCOUNTABILITY CHECK START ==========")
        print("🔍 Timestamp: \(Date())")
        
        print("🔍 Step 1: Loading tasks...")
        let tasks = taskManager.loadTasks()
        print("🔍 Total tasks loaded: \(tasks.count)")
        
        let today = Calendar.current.startOfDay(for: Date())
        print("🔍 Today's date: \(today)")
        
        // Get tasks due today or overdue
        let dueTasks = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            let taskDueDate = Calendar.current.startOfDay(for: dueDate)
            return taskDueDate <= today && task.status != .done && task.status != .cancelled
        }
        
        guard !dueTasks.isEmpty else {
            print("✅ No overdue or due tasks")
            print("🔍 ========== ACCOUNTABILITY CHECK COMPLETE (NOTHING TO CHECK) ==========")
            return AccountabilityReport(unmentionedTasks: [], overdueTasksCount: 0)
        }
        
        print("🔍 Step 2: Found \(dueTasks.count) tasks due today or overdue")
        for (index, task) in dueTasks.enumerated() {
            print("   Task \(index + 1): \(task.title) (Due: \(task.dueDate?.description ?? "N/A"), Status: \(task.status))")
        }
        
        // Read today's journal to see what was mentioned
        print("🔍 Step 3: Reading today's journal...")
        let todayJournal = fileManager.loadCurrentWeekDetailedJournal()
        print("🔍 Journal length: \(todayJournal.count) characters")
        
        let todayEntries = extractTodayEntries(from: todayJournal)
        print("🔍 Today's entries length: \(todayEntries.count) characters")
        print("🔍 Today's entries preview: \(todayEntries.prefix(200))...")
        
        // Check which tasks weren't mentioned
        print("🔍 Step 4: Checking which tasks were mentioned...")
        var unmentionedTasks: [TaskItem] = []
        
        for task in dueTasks {
            let wasMentioned = todayEntries.localizedCaseInsensitiveContains(task.title) ||
                               todayEntries.localizedCaseInsensitiveContains("completed") ||
                               todayEntries.localizedCaseInsensitiveContains("done") ||
                               todayEntries.localizedCaseInsensitiveContains("finished")
            
            if !wasMentioned {
                unmentionedTasks.append(task)
                print("   ⚠️ Task NOT mentioned: \(task.title)")
            } else {
                print("   ✅ Task mentioned: \(task.title)")
            }
        }
        
        let overdueCount = dueTasks.filter { $0.isOverdue }.count
        
        print("✅ ========== ACCOUNTABILITY CHECK COMPLETE ==========")
        print("📊 Found \(unmentionedTasks.count) unmentioned tasks, \(overdueCount) overdue")
        
        return AccountabilityReport(
            unmentionedTasks: unmentionedTasks,
            overdueTasksCount: overdueCount
        )
    }
    
    /// Generate a natural accountability prompt for Claude to use
    func generateAccountabilityPrompt(for report: AccountabilityReport) -> String? {
        guard !report.unmentionedTasks.isEmpty else {
            return nil
        }
        
        var prompt = "I noticed you had some tasks due today that you didn't mention:\n\n"
        
        for task in report.unmentionedTasks.prefix(5) { // Limit to 5 to avoid overwhelming
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            let dueDateStr = task.dueDate.map { dateFormatter.string(from: $0) } ?? "today"
            
            let overdueFlag = task.isOverdue ? " (OVERDUE)" : ""
            prompt += "- **\(task.title)** (Due: \(dueDateStr))\(overdueFlag)\n"
            if let assignee = task.assignee as String?, assignee.lowercased() != "me" {
                prompt += "  Assigned to: \(assignee)\n"
            }
        }
        
        prompt += "\nDid you complete any of these? Let me know so I can update your task list."
        
        return prompt
    }
    
    /// Check for tasks assigned to others that are overdue (waiting on someone)
    func checkWaitingOnTasks() -> [TaskItem] {
        let tasks = taskManager.loadTasks()
        let today = Date()
        
        let waitingOnTasks = tasks.filter { task in
            guard let dueDate = task.dueDate else { return false }
            return task.assignee.lowercased() != "me" &&
                   dueDate < today &&
                   task.status != .done &&
                   task.status != .cancelled
        }
        
        return waitingOnTasks
    }
    
    /// Generate prompt for tasks waiting on others
    func generateWaitingOnPrompt(for tasks: [TaskItem]) -> String? {
        guard !tasks.isEmpty else {
            return nil
        }
        
        var prompt = "You're waiting on some people who haven't completed their tasks:\n\n"
        
        for task in tasks.prefix(5) {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .short
            let dueDateStr = task.dueDate.map { dateFormatter.string(from: $0) } ?? "unknown"
            
            prompt += "- **\(task.assignee)**: \(task.title) (was due \(dueDateStr))\n"
        }
        
        prompt += "\nShould I remind you to follow up with any of them?"
        
        return prompt
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
}

// MARK: - Data Models

struct AccountabilityReport {
    let unmentionedTasks: [TaskItem]
    let overdueTasksCount: Int
    
    var hasIssues: Bool {
        !unmentionedTasks.isEmpty || overdueTasksCount > 0
    }
}
