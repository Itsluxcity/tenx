import SwiftUI

struct HousekeepingView: View {
    @EnvironmentObject var appState: AppState
    @State private var isRunning = false
    @State private var result: HousekeepingResult?
    @State private var showingResult = false
    @State private var activityLog: [ActivityLogEntry] = []
    @State private var showingActivityLog = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 24) {
            if isRunning {
                // Running state with live progress
                VStack(spacing: 24) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .padding()
                    
                    Text("Running Housekeeping...")
                        .font(.title3)
                        .fontWeight(.semibold)
                    
                    // Live activity log
                    if !activityLog.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Progress:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            ScrollViewReader { proxy in
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(activityLog.suffix(15)) { entry in
                                            HStack(alignment: .top, spacing: 8) {
                                                Image(systemName: entry.type.icon)
                                                    .foregroundColor(entry.type.color)
                                                    .font(.caption)
                                                    .frame(width: 16)
                                                
                                                Text(entry.message)
                                                    .font(.caption)
                                                    .foregroundColor(.primary)
                                            }
                                            .id(entry.id)
                                        }
                                    }
                                }
                                .frame(maxHeight: 300)
                                .onChange(of: activityLog.count) { _ in
                                    if let lastEntry = activityLog.last {
                                        withAnimation {
                                            proxy.scrollTo(lastEntry.id, anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                .padding()
                
            } else {
                // Normal state - Header
                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Housekeeping")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Automatically maintain your data")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 40)
            
            // What it does
            VStack(alignment: .leading, spacing: 16) {
                Text("What Housekeeping Does:")
                    .font(.headline)
                
                FeatureRow(icon: "magnifyingglass", title: "Scans Journal", description: "Reads today's journal entries")
                FeatureRow(icon: "plus.circle", title: "Creates Missing Items", description: "Adds tasks, events, and reminders you mentioned but didn't create")
                FeatureRow(icon: "trash", title: "Removes Duplicates", description: "Finds and merges duplicate tasks and reminders")
                FeatureRow(icon: "checkmark.shield", title: "Ensures Consistency", description: "Keeps everything organized and up-to-date")
            }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                Spacer()
                
                // Activity Log Button
                if !activityLog.isEmpty {
                    Button(action: {
                        showingActivityLog = true
                    }) {
                        HStack {
                            Image(systemName: "list.bullet.rectangle")
                            Text("View Activity Log (\(activityLog.count) entries)")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.gray.opacity(0.2))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                    }
                }
                
                // Run button
                Button(action: {
                    Task {
                        await runHousekeeping()
                    }
                }) {
                    HStack {
                        Image(systemName: "play.fill")
                        Text("Run Housekeeping Now")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                // Last run info
                if let lastRun = UserDefaults.standard.object(forKey: "last_housekeeping_run_date") as? Date {
                    Text("Last run: \(formatDate(lastRun))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .navigationTitle("Housekeeping")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingResult) {
            if let result = result {
                HousekeepingResultView(result: result)
            }
        }
        .sheet(isPresented: $showingActivityLog) {
            ActivityLogView(entries: activityLog)
        }
        .onAppear {
            loadActivityLog()
        }
    }
    
    private func runHousekeeping() async {
        isRunning = true
        activityLog = [] // Clear previous log
        
        // Add start entry
        addLogEntry("🧹 Housekeeping Started", type: .info)
        
        // Set up progress callback to receive live updates
        appState.housekeepingService.onProgress = { message in
            Task { @MainActor in
                self.addLogEntry(message, type: self.getLogType(for: message))
            }
        }
        
        let housekeepingResult = await appState.runHousekeepingNow()
        
        // Add final summary entries
        addLogEntry("📊 Final Results:", type: .info)
        addLogEntry("Found \(housekeepingResult.gapsFound) gaps", type: .info)
        addLogEntry("Created \(housekeepingResult.tasksCreated) tasks", type: .success)
        addLogEntry("Created \(housekeepingResult.eventsCreated) events", type: .success)
        addLogEntry("Created \(housekeepingResult.remindersCreated) reminders", type: .success)
        addLogEntry("Deduplicated \(housekeepingResult.tasksDeduplicated) tasks", type: .success)
        addLogEntry("Deduplicated \(housekeepingResult.remindersDeduplicated) reminders", type: .success)
        
        if !housekeepingResult.errors.isEmpty {
            for error in housekeepingResult.errors {
                addLogEntry("❌ Error: \(error)", type: .error)
            }
        }
        
        // Save log to file
        saveActivityLog()
        
        isRunning = false
        result = housekeepingResult
        showingResult = true
    }
    
    private func getLogType(for message: String) -> ActivityLogEntry.EntryType {
        if message.contains("✅") || message.contains("🎉") {
            return .success
        } else if message.contains("⚠️") || message.contains("❌") {
            return .error
        } else {
            return .info
        }
    }
    
    private func addLogEntry(_ message: String, type: ActivityLogEntry.EntryType) {
        let entry = ActivityLogEntry(
            timestamp: Date(),
            message: message,
            type: type
        )
        activityLog.append(entry)
    }
    
    private func saveActivityLog() {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let logContent = activityLog.map { entry in
            let timeStr = DateFormatter.localizedString(from: entry.timestamp, dateStyle: .none, timeStyle: .medium)
            return "[\(timeStr)] \(entry.message)"
        }.joined(separator: "\n")
        
        let logFile = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("housekeeping-activity-\(timestamp).log")
        
        try? logContent.write(to: logFile, atomically: true, encoding: .utf8)
    }
    
    private func loadActivityLog() {
        // Load most recent activity log if exists
        let docsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let files = try? FileManager.default.contentsOfDirectory(at: docsDir, includingPropertiesForKeys: [.creationDateKey]) else {
            return
        }
        
        let logFiles = files.filter { $0.lastPathComponent.hasPrefix("housekeeping-activity-") }
            .sorted { f1, f2 in
                let date1 = (try? f1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let date2 = (try? f2.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return date1 > date2
            }
        
        if let mostRecent = logFiles.first,
           let content = try? String(contentsOf: mostRecent) {
            // Parse log file back into entries
            let lines = content.components(separatedBy: "\n")
            activityLog = lines.compactMap { line in
                guard !line.isEmpty else { return nil }
                // Simple parsing - just store as info type
                return ActivityLogEntry(
                    timestamp: Date(),
                    message: line,
                    type: .info
                )
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct HousekeepingResultView: View {
    let result: HousekeepingResult
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var showGaps = false
    @State private var showTasks = false
    @State private var showEvents = false
    @State private var showReminders = false
    @State private var navigateToAIItems = false
    @State private var selectedTab = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Success icon
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                        .padding(.top, 20)
                    
                    Text("Housekeeping Complete!")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Results with expandable sections
                    VStack(spacing: 16) {
                        // Gaps Found (expandable)
                        ExpandableResultRow(
                            icon: "magnifyingglass",
                            label: "Gaps Found",
                            value: "\(result.gapsFound)",
                            isExpanded: $showGaps,
                            items: result.gaps.map { "\($0.type == .missingTask ? "📝" : $0.type == .missingCalendarEvent ? "📅" : "🔔") \($0.description.prefix(60))..." }
                        )
                        
                        Divider()
                        
                        // Tasks Created (expandable)
                        ExpandableResultRow(
                            icon: "plus.circle.fill",
                            label: "Tasks Created",
                            value: "\(result.tasksCreated)",
                            color: .blue,
                            isExpanded: $showTasks,
                            items: result.createdTaskTitles
                        )
                        
                        // Events Created (expandable)
                        ExpandableResultRow(
                            icon: "calendar.badge.plus",
                            label: "Events Created",
                            value: "\(result.eventsCreated)",
                            color: .red,
                            isExpanded: $showEvents,
                            items: result.createdEventTitles
                        )
                        
                        // Reminders Created (expandable)
                        ExpandableResultRow(
                            icon: "bell.badge.fill",
                            label: "Reminders Created",
                            value: "\(result.remindersCreated)",
                            color: .orange,
                            isExpanded: $showReminders,
                            items: result.createdReminderTitles
                        )
                        
                        Divider()
                        
                        ResultRow(icon: "trash.fill", label: "Events Deduplicated", value: "\(result.eventsDeduplicated)", color: .purple)
                        ResultRow(icon: "trash.fill", label: "Tasks Deduplicated", value: "\(result.tasksDeduplicated)", color: .purple)
                        ResultRow(icon: "trash.fill", label: "Reminders Deduplicated", value: "\(result.remindersDeduplicated)", color: .purple)
                    }
                    .padding()
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(12)
                    
                    // Errors (if any)
                    if !result.errors.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Errors", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundColor(.red)
                            
                            ForEach(result.errors, id: \.self) { error in
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Summary
                    Text(result.summary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                    
                    // View in AI Items button
                    if result.tasksCreated > 0 || result.eventsCreated > 0 || result.remindersCreated > 0 {
                        Button(action: {
                            // Dismiss this view and user can navigate to AI Items tab manually
                            dismiss()
                        }) {
                            HStack {
                                Image(systemName: "sparkles")
                                Text("View All AI Items in Tab")
                                Image(systemName: "arrow.right")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                }
                .padding()
            }
            .navigationTitle("Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ExpandableResultRow: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = .primary
    @Binding var isExpanded: Bool
    let items: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                if !items.isEmpty {
                    withAnimation {
                        isExpanded.toggle()
                    }
                }
            }) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .frame(width: 24)
                    
                    Text(label)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(value)
                        .font(.headline)
                        .foregroundColor(color)
                    
                    if !items.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            
            if isExpanded && !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        Text("• \(item)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 28)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

struct ResultRow: View {
    let icon: String
    let label: String
    let value: String
    var color: Color = .primary
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            Text(label)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.headline)
                .foregroundColor(color)
        }
    }
}

// MARK: - Activity Log

struct ActivityLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: EntryType
    
    enum EntryType {
        case info
        case success
        case error
        case warning
        
        var color: Color {
            switch self {
            case .info: return .primary
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }
    }
}

struct ActivityLogView: View {
    let entries: [ActivityLogEntry]
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(entries) { entry in
                        ActivityLogRow(entry: entry)
                    }
                }
                .padding()
            }
            .navigationTitle("Activity Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        shareLog()
                    }) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
    
    private func shareLog() {
        let logText = entries.map { entry in
            let timeStr = DateFormatter.localizedString(from: entry.timestamp, dateStyle: .none, timeStyle: .medium)
            return "[\(timeStr)] \(entry.message)"
        }.joined(separator: "\n")
        
        let activityVC = UIActivityViewController(
            activityItems: [logText],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

struct ActivityLogRow: View {
    let entry: ActivityLogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.type.icon)
                .foregroundColor(entry.type.color)
                .font(.title3)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                
                Text(formatTime(entry.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(entry.type.color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }
}
