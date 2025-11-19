import SwiftUI
import EventKit

struct AIItemsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSegment = 0
    @State private var showHousekeeping = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Big action buttons
                HStack(spacing: 12) {
                    // Housekeeping button
                    Button(action: {
                        showHousekeeping = true
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                                .font(.system(size: 32))
                            Text("Run Housekeeping")
                                .font(.caption)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                // Segment control
                Picker("Item Type", selection: $selectedSegment) {
                    Text("Tasks").tag(0)
                    Text("Events").tag(1)
                    Text("Reminders").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content based on selection
                switch selectedSegment {
                case 0:
                    AITasksListView()
                case 1:
                    AIEventsListView()
                case 2:
                    AIRemindersListView()
                default:
                    EmptyView()
                }
            }
            .navigationTitle("AI Created Items")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showHousekeeping) {
                HousekeepingView()
                    .environmentObject(appState)
            }
        }
    }
}

// MARK: - AI Tasks List

struct AITasksListView: View {
    @EnvironmentObject var appState: AppState
    
    var aiCreatedTasks: [TaskItem] {
        appState.tasks.filter { $0.description?.contains("Auto-created by housekeeping") ?? false }
    }
    
    var manualTasks: [TaskItem] {
        appState.tasks.filter { !($0.description?.contains("Auto-created by housekeeping") ?? false) }
    }
    
    var body: some View {
        List {
            if !aiCreatedTasks.isEmpty {
                Section(header: Text("🤖 AI Created (\(aiCreatedTasks.count))")) {
                    ForEach(aiCreatedTasks) { task in
                        AITaskRow(task: task)
                    }
                }
            }
            
            if !manualTasks.isEmpty {
                Section(header: Text("✋ Manual (\(manualTasks.count))")) {
                    ForEach(manualTasks) { task in
                        AITaskRow(task: task)
                    }
                }
            }
            
            if aiCreatedTasks.isEmpty && manualTasks.isEmpty {
                Text("No tasks yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
    }
}

struct AITaskRow: View {
    let task: TaskItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.headline)
            
            HStack {
                Label(task.assignee, systemImage: "person.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let dueDate = task.dueDate {
                    Label(formatDate(dueDate), systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(isOverdue(dueDate) ? .red : .secondary)
                }
            }
            
            // Show creation time for AI-created tasks
            if task.description?.contains("Auto-created by housekeeping") ?? false {
                Label("Created: \(formatDateTime(task.createdAt))", systemImage: "clock.fill")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            
            if task.status == .done {
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        return date < Date() && Calendar.current.isDateInToday(date) == false
    }
}

// MARK: - AI Events List

struct AIEventsListView: View {
    @EnvironmentObject var appState: AppState
    @State private var aiEvents: [EKEvent] = []
    @State private var manualEvents: [EKEvent] = []
    
    var body: some View {
        List {
            if !aiEvents.isEmpty {
                Section(header: Text("🤖 AI Created (\(aiEvents.count))")) {
                    ForEach(aiEvents, id: \.eventIdentifier) { event in
                        AIEventRow(event: event)
                    }
                }
            }
            
            if !manualEvents.isEmpty {
                Section(header: Text("✋ Manual (\(manualEvents.count))")) {
                    ForEach(manualEvents, id: \.eventIdentifier) { event in
                        AIEventRow(event: event)
                    }
                }
            }
            
            if aiEvents.isEmpty && manualEvents.isEmpty {
                Text("No events yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .onAppear {
            loadEvents()
        }
        .refreshable {
            loadEvents()
        }
    }
    
    private func loadEvents() {
        let recentEvents = appState.eventKitManager.fetchRecentEvents(daysBehind: 7)
        let upcomingEvents = appState.eventKitManager.fetchUpcomingEvents(daysAhead: 30)
        
        let allEvents = recentEvents + upcomingEvents
        
        aiEvents = allEvents.filter { event in
            event.notes?.contains("Auto-created by housekeeping") ?? false
        }
        
        manualEvents = allEvents.filter { event in
            !(event.notes?.contains("Auto-created by housekeeping") ?? false)
        }
    }
}

struct AIEventRow: View {
    let event: EKEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(event.title ?? "Untitled Event")
                .font(.headline)
            
            if let startDate = event.startDate {
                HStack {
                    Label(formatDateTime(startDate), systemImage: "calendar")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let endDate = event.endDate {
                        Text("→")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text(formatTime(endDate))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Show creation time for AI-created events
            if event.notes?.contains("Auto-created by housekeeping") ?? false, let creationDate = event.creationDate {
                Label("Created: \(formatDateTime(creationDate))", systemImage: "clock.fill")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            
            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.circle.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - AI Reminders List

struct AIRemindersListView: View {
    @EnvironmentObject var appState: AppState
    @State private var aiReminders: [EKReminder] = []
    @State private var manualReminders: [EKReminder] = []
    
    var body: some View {
        List {
            if !aiReminders.isEmpty {
                Section(header: Text("🤖 AI Created (\(aiReminders.count))")) {
                    ForEach(aiReminders, id: \.calendarItemIdentifier) { reminder in
                        AIReminderRow(reminder: reminder)
                    }
                }
            }
            
            if !manualReminders.isEmpty {
                Section(header: Text("✋ Manual (\(manualReminders.count))")) {
                    ForEach(manualReminders, id: \.calendarItemIdentifier) { reminder in
                        AIReminderRow(reminder: reminder)
                    }
                }
            }
            
            if aiReminders.isEmpty && manualReminders.isEmpty {
                Text("No reminders yet")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            }
        }
        .onAppear {
            loadReminders()
        }
        .refreshable {
            loadReminders()
        }
    }
    
    private func loadReminders() {
        let allReminders = appState.eventKitManager.fetchReminders(includeCompleted: false)
        
        aiReminders = allReminders.filter { reminder in
            reminder.notes?.contains("Auto-created by housekeeping") ?? false
        }
        
        manualReminders = allReminders.filter { reminder in
            !(reminder.notes?.contains("Auto-created by housekeeping") ?? false)
        }
    }
}

struct AIReminderRow: View {
    let reminder: EKReminder
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(reminder.title ?? "Untitled Reminder")
                .font(.headline)
            
            if let dueDate = reminder.dueDateComponents?.date {
                Label(formatDate(dueDate), systemImage: "bell.fill")
                    .font(.caption)
                    .foregroundColor(isOverdue(dueDate) ? .red : .secondary)
            }
            
            // Show creation time for AI-created reminders
            if reminder.notes?.contains("Auto-created by housekeeping") ?? false, let creationDate = reminder.creationDate {
                Label("Created: \(formatDateTime(creationDate))", systemImage: "clock.fill")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
            
            if reminder.isCompleted {
                Label("Completed", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func isOverdue(_ date: Date) -> Bool {
        return date < Date()
    }
}
