import SwiftUI

struct ChatView: View {
    @EnvironmentObject var appState: AppState
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @State private var showingHistory = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Messages list
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(appState.messages) { message in
                                MessageBubble(message: message)
                                    .environmentObject(appState)
                                    .id(message.id)
                            }
                        }
                        .padding()
                    }
                    .onTapGesture {
                        // Dismiss keyboard when tapping on messages
                        isInputFocused = false
                    }
                    .onChange(of: appState.messages.count) { _ in
                        if let lastMessage = appState.messages.last {
                            withAnimation {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // Recording view or input bar
                if appState.isRecording {
                    RecordingView()
                } else {
                    InputBar(inputText: $inputText, isInputFocused: _isInputFocused)
                }
            }
            .navigationTitle(appState.currentSession?.title ?? "TenX")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingHistory = true }) {
                        Image(systemName: "list.bullet")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        appState.createNewSession()
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isInputFocused = false
                    }
                }
            }
            .sheet(isPresented: $showingHistory) {
                ChatHistoryView()
                    .environmentObject(appState)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 20)
                    .onChanged { value in
                        // Dismiss keyboard on swipe down (more responsive)
                        if value.translation.height > 30 && isInputFocused {
                            isInputFocused = false
                        }
                    }
            )
            .onAppear {
                // Pre-fill transcript if available
                if !appState.currentTranscript.isEmpty {
                    inputText = appState.currentTranscript
                }
            }
            .onChange(of: appState.currentTranscript) { newValue in
                inputText = newValue
                isInputFocused = true
            }
        }
    }
}

struct MessageBubble: View {
    @EnvironmentObject var appState: AppState
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                Text(message.content)
                    .padding(12)
                    .background(message.role == .user ? Color.blue : Color.gray.opacity(0.2))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)
                    .contextMenu {
                        Button(action: {
                            UIPasteboard.general.string = message.content
                        }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                
                // Show attachments (tasks, reminders, calendar events)
                if let attachments = message.attachments {
                    ForEach(attachments) { attachment in
                        AttachmentView(attachment: attachment)
                            .environmentObject(appState)
                    }
                }
                
                // Show live progress for the last message
                if message.id == appState.messages.last?.id && !appState.currentToolProgress.isEmpty {
                    ToolProgressView(progress: appState.currentToolProgress)
                }
                
                Text(formatTime(message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 280, alignment: message.role == .user ? .trailing : .leading)
            
            if message.role == .assistant {
                Spacer()
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct InputBar: View {
    @EnvironmentObject var appState: AppState
    @Binding var inputText: String
    @FocusState var isInputFocused: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            TextField("Type a message...", text: $inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .focused($isInputFocused)
                .lineLimit(1...5)
            
            Button(action: {
                Task {
                    await appState.sendMessage(inputText)
                    inputText = ""
                }
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(inputText.isEmpty ? .gray : .blue)
            }
            .disabled(inputText.isEmpty)
            
            Button(action: {
                if appState.isRecording {
                    Task {
                        await appState.stopRecording()
                    }
                } else {
                    appState.startRecording()
                }
            }) {
                Image(systemName: appState.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(appState.isRecording ? .red : .blue)
            }
        }
        .padding()
    }
}

struct RecordingView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        VStack(spacing: 16) {
            // Waveform visualization
            WaveformView(audioLevels: appState.audioManager.audioLevels)
                .frame(height: 100)
                .padding(.horizontal)
            
            // Timer
            Text(formatDuration(appState.recordingDuration))
                .font(.system(size: 48, weight: .light, design: .monospaced))
                .foregroundColor(.red)
            
            Text("Recording...")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // Stop button
            Button(action: {
                Task {
                    await appState.stopRecording()
                }
            }) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.red)
            }
            .padding(.bottom)
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct AttachmentView: View {
    let attachment: MessageAttachment
    @Environment(\.openURL) var openURL
    @EnvironmentObject var appState: AppState
    @State private var selectedTask: TaskItem?
    
    var body: some View {
        Button(action: handleAttachmentTap) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.title3)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(attachment.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    if let subtitle = attachment.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(item: $selectedTask) { task in
            NavigationView {
                TaskDetailView(task: task)
                    .environmentObject(appState)
            }
        }
    }
    
    private var iconName: String {
        switch attachment.type {
        case .task: return "checkmark.circle.fill"
        case .reminder: return "bell.fill"
        case .calendarEvent: return "calendar"
        }
    }
    
    private var iconColor: Color {
        switch attachment.type {
        case .task: return .blue
        case .reminder: return .orange
        case .calendarEvent: return .red
        }
    }
    
    private func handleAttachmentTap() {
        switch attachment.type {
        case .task:
            // Check if it's a person file or search result (not an actual task)
            if attachment.title.starts(with: "Person:") || attachment.title.contains("Search Results") {
                // These are informational attachments, not clickable tasks
                print("ℹ️  Informational attachment: \(attachment.title)")
                return
            }
            
            // Find and show task
            print("🔍 Looking for task with ID: \(attachment.actionData)")
            print("🔍 Available tasks count: \(appState.tasks.count)")
            
            if let taskId = UUID(uuidString: attachment.actionData) {
                print("🔍 Parsed UUID: \(taskId)")
                if let task = appState.tasks.first(where: { $0.id == taskId }) {
                    print("✅ Found task: \(task.title)")
                    selectedTask = task
                } else {
                    print("⚠️ Task not found in appState.tasks")
                    print("⚠️ Available task IDs:")
                    for t in appState.tasks {
                        print("   - \(t.id.uuidString): \(t.title)")
                    }
                }
            } else {
                print("❌ Failed to parse UUID from: \(attachment.actionData)")
            }
        case .reminder:
            // iOS doesn't support opening specific reminders via URL scheme
            // Just open the Reminders app
            if let url = URL(string: "x-apple-reminderkit://") {
                print("📱 Opening Reminders app (iOS doesn't support deep links to specific reminders)")
                openURL(url)
            }
        case .calendarEvent:
            // Open calendar at specific date using timeIntervalSinceReferenceDate
            if !attachment.actionData.isEmpty {
                let urlString = "calshow:\(attachment.actionData)"
                if let url = URL(string: urlString) {
                    print("📅 Opening calendar with URL: \(urlString)")
                    openURL(url)
                } else {
                    print("❌ Failed to create calendar URL from: \(attachment.actionData)")
                }
            } else {
                // Fallback to just opening the app
                if let url = URL(string: "calshow://") {
                    openURL(url)
                }
            }
        }
    }
}

struct ToolProgressView: View {
    let progress: [ToolProgress]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(progress) { item in
                HStack(spacing: 12) {
                    Image(systemName: item.icon)
                        .foregroundColor(iconColor(for: item.status))
                        .font(.system(size: 16))
                        .frame(width: 20)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.description)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        
                        if item.status == .inProgress {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(height: 4)
                        }
                    }
                    
                    Spacer()
                }
                .padding(.vertical, 4)
                
                // Show attachment when completed
                if item.status == .completed, let attachment = item.attachment {
                    AttachmentView(attachment: attachment)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .padding(12)
        .background(Color.gray.opacity(0.1))
        .cornerRadius(12)
    }
    
    private func iconColor(for status: ToolProgress.ToolStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

struct WaveformView: View {
    let audioLevels: [Float]
    
    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<min(audioLevels.count, 100), id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.red)
                        .frame(width: max(2, geometry.size.width / 100 - 2),
                               height: max(4, CGFloat(audioLevels[index]) * geometry.size.height))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
