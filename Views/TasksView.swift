import SwiftUI

struct TasksView: View {
    @EnvironmentObject var appState: AppState
    @State private var filterStatus: TaskStatus? = nil
    @State private var filterCompany: String? = nil
    @State private var showingAddTask = false
    
    var filteredTasks: [TaskItem] {
        appState.tasks.filter { task in
            if let status = filterStatus, task.status != status {
                return false
            }
            if let company = filterCompany, task.company != company {
                return false
            }
            return true
        }
    }
    
    var companies: [String] {
        Array(Set(appState.tasks.compactMap { $0.company })).sorted()
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Filters - compact
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "All", isSelected: filterStatus == nil) {
                            filterStatus = nil
                        }
                        
                        FilterChip(title: "Pending", isSelected: filterStatus == .pending) {
                            filterStatus = .pending
                        }
                        
                        FilterChip(title: "In Progress", isSelected: filterStatus == .inProgress) {
                            filterStatus = .inProgress
                        }
                        
                        FilterChip(title: "Done", isSelected: filterStatus == .done) {
                            filterStatus = .done
                        }
                        
                        if !companies.isEmpty {
                            Divider()
                                .frame(height: 20)
                            
                            ForEach(companies, id: \.self) { company in
                                FilterChip(title: company, isSelected: filterCompany == company) {
                                    filterCompany = filterCompany == company ? nil : company
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(Color(uiColor: .systemBackground))
                
                // Tasks list
                List {
                    ForEach(filteredTasks) { task in
                        NavigationLink(destination: TaskDetailView(task: task)) {
                            TaskRow(task: task)
                        }
                    }
                    .onDelete { indexSet in
                        deleteTask(at: indexSet)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Tasks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingAddTask = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTask) {
                AddTaskView()
                    .environmentObject(appState)
            }
        }
    }
    
    private func deleteTask(at offsets: IndexSet) {
        for index in offsets {
            let task = filteredTasks[index]
            // Delete from task manager
            var allTasks = appState.taskManager.loadTasks()
            allTasks.removeAll { $0.id == task.id }
            appState.taskManager.saveTasks(allTasks)
            appState.tasks = appState.taskManager.loadTasks()
        }
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .foregroundColor(isSelected ? .white : .primary)
                .cornerRadius(16)
        }
    }
}

struct TaskRow: View {
    @EnvironmentObject var appState: AppState
    let task: TaskItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.status == .done ? .green : .gray)
                    .onTapGesture {
                        appState.taskManager.toggleTaskComplete(taskId: task.id.uuidString)
                        appState.tasks = appState.taskManager.loadTasks()
                    }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.headline)
                        .strikethrough(task.status == .done)
                    
                    if let description = task.description {
                        Text(description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                    
                    HStack(spacing: 12) {
                        Label(task.assignee, systemImage: "person.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let company = task.company {
                            Label(company, systemImage: "building.2.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let dueDate = task.dueDate {
                            Label(formatDate(dueDate), systemImage: "calendar")
                                .font(.caption)
                                .foregroundColor(task.isOverdue ? .red : .secondary)
                        }
                    }
                }
                
                Spacer()
                
                if task.isOverdue {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

struct AddTaskView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    
    @State private var title = ""
    @State private var description = ""
    @State private var assignee = "me"
    @State private var company = ""
    @State private var dueDate = Date()
    @State private var hasDueDate = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Task Details") {
                    TextField("Title", text: $title)
                    TextField("Description (optional)", text: $description)
                    TextField("Assignee", text: $assignee)
                    TextField("Company (optional)", text: $company)
                }
                
                Section("Due Date") {
                    Toggle("Set due date", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Due date", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
            }
            .navigationTitle("Add Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        addTask()
                    }
                    .disabled(title.isEmpty)
                }
            }
        }
    }
    
    private func addTask() {
        let task = TaskItem(
            title: title,
            description: description.isEmpty ? nil : description,
            company: company.isEmpty ? nil : company,
            assignee: assignee,
            dueDate: hasDueDate ? dueDate : nil,
            status: .pending
        )
        
        appState.taskManager.createOrUpdateTask(task)
        appState.tasks = appState.taskManager.loadTasks()
        dismiss()
    }
}

struct TaskDetailView: View {
    @EnvironmentObject var appState: AppState
    let task: TaskItem
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Title
                Text(task.title)
                    .font(.largeTitle)
                    .bold()
                
                // Status
                HStack {
                    Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(task.status == .done ? .green : .gray)
                        .font(.title2)
                    
                    Text(task.status.rawValue.capitalized)
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(task.status == .done ? "Mark Incomplete" : "Mark Complete") {
                        appState.taskManager.toggleTaskComplete(taskId: task.id.uuidString)
                        appState.tasks = appState.taskManager.loadTasks()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                Divider()
                
                // Description
                if let description = task.description {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.headline)
                        Text(description)
                            .font(.body)
                    }
                }
                
                // Details
                VStack(alignment: .leading, spacing: 12) {
                    Text("Details")
                        .font(.headline)
                    
                    HStack {
                        Label("Assignee", systemImage: "person.fill")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(task.assignee)
                    }
                    
                    if let company = task.company {
                        HStack {
                            Label("Company", systemImage: "building.2.fill")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(company)
                        }
                    }
                    
                    if let dueDate = task.dueDate {
                        HStack {
                            Label("Due Date", systemImage: "calendar")
                                .foregroundColor(task.isOverdue ? .red : .secondary)
                            Spacer()
                            Text(formatDate(dueDate))
                                .foregroundColor(task.isOverdue ? .red : .primary)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Task Details")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct TaskRow_Previews: PreviewProvider {
    static var previews: some View {
        TaskRow(task: TaskItem(
            title: "Test Task",
            description: "Test description",
            company: "Test Co",
            assignee: "John",
            dueDate: Date(),
            status: .pending
        ))
        .environmentObject(AppState())
    }
}
