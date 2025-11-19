# Working State One - Complete Implementation Guide

**Date**: November 16, 2025  
**Status**: ✅ All Core Features Working

This document describes the exact implementation details for all working features in TenX. Use this as a reference to restore functionality if something breaks.

---

## Table of Contents
1. [Task Attachments - Opening Task Details](#1-task-attachments---opening-task-details)
2. [Calendar Event Deep Links](#2-calendar-event-deep-links)
3. [Reminder Creation](#3-reminder-creation)
4. [Journal View & Edit](#4-journal-view--edit)
5. [Claude Context & Rescheduling](#5-claude-context--rescheduling)
6. [Tasks View UI](#6-tasks-view-ui)

---

## 1. Task Attachments - Opening Task Details

### Problem
When tapping a task attachment in chat, it opened a blank sheet instead of showing task details.

### Root Cause
Using `sheet(isPresented:)` with an optional binding caused a timing issue where the sheet opened before `selectedTask` was set.

### Solution
**File**: `Views/ChatView.swift`

**Key Technology**: SwiftUI `sheet(item:)` modifier

```swift
struct AttachmentView: View {
    let attachment: MessageAttachment
    @Environment(\.openURL) var openURL
    @EnvironmentObject var appState: AppState
    @State private var selectedTask: TaskItem?
    
    var body: some View {
        Button(action: handleAttachmentTap) {
            // ... button UI ...
        }
        .buttonStyle(PlainButtonStyle())
        // ✅ CRITICAL: Use sheet(item:) NOT sheet(isPresented:)
        .sheet(item: $selectedTask) { task in
            NavigationView {
                TaskDetailView(task: task)
                    .environmentObject(appState)
            }
        }
    }
    
    private func handleAttachmentTap() {
        switch attachment.type {
        case .task:
            if let taskId = UUID(uuidString: attachment.actionData),
               let task = appState.tasks.first(where: { $0.id == taskId }) {
                // ✅ Setting selectedTask automatically triggers sheet
                selectedTask = task
            }
        // ... other cases ...
        }
    }
}
```

**Why This Works**:
- `sheet(item:)` waits for the binding to be non-nil before showing
- Automatically passes the unwrapped value to the closure
- No race condition between setting state and showing sheet

**Must Pass EnvironmentObject**:
```swift
// In MessageBubble, when creating AttachmentView:
ForEach(attachments) { attachment in
    AttachmentView(attachment: attachment)
        .environmentObject(appState)  // ✅ REQUIRED
}
```

---

## 2. Calendar Event Deep Links

### Problem
Calendar events opened to December 31, 2000 instead of the actual event date.

### Root Cause
Attempted to use event ID with `calshow:` URL scheme, but iOS Calendar uses `timeIntervalSinceReferenceDate`.

### Solution
**Files**: 
- `Models/AppState.swift` (executeToolCall)
- `Services/EventKitManager.swift` (createEvent)
- `Views/ChatView.swift` (handleAttachmentTap)

**Key Technology**: iOS `calshow:` URL scheme with `timeIntervalSinceReferenceDate`

#### Step 1: Store the correct data in AppState
```swift
case "create_calendar_event":
    let title = toolCall.args["title"] as? String ?? ""
    let start = parseDate(toolCall.args["start"] as? String) ?? Date()
    let end = parseDate(toolCall.args["end"] as? String) ?? Date()
    
    let eventId = await eventKitManager.createEvent(
        title: title,
        start: start,
        end: end,
        notes: toolCall.args["notes"] as? String
    )
    
    // ✅ CRITICAL: Store timeIntervalSinceReferenceDate, NOT event ID
    return MessageAttachment(
        type: .calendarEvent,
        title: title,
        subtitle: dateFormatter.string(from: start),
        actionData: "\(start.timeIntervalSinceReferenceDate)"  // ✅ This is the key
    )
```

#### Step 2: Use correct URL format in ChatView
```swift
case .calendarEvent:
    if !attachment.actionData.isEmpty {
        // ✅ Format: calshow:[timeIntervalSinceReferenceDate]
        let urlString = "calshow:\(attachment.actionData)"
        if let url = URL(string: urlString) {
            openURL(url)
        }
    }
```

**Why This Works**:
- `timeIntervalSinceReferenceDate` is the number of seconds since January 1, 2001
- iOS Calendar app uses this format to navigate to specific dates
- Example: `calshow:785095200.0` opens to November 17, 2025 at 10:00 AM

**Reference**: Stack Overflow - "How to open calendar with event - NSURL calshow:"

---

## 3. Reminder Creation

### Problem
Reminders weren't being created in the iOS Reminders app.

### Root Cause
Code was checking `settings.autoAddToCalendar` before creating reminders.

### Solution
**File**: `Models/AppState.swift`

**Key Technology**: EventKit `EKReminder` with proper authorization checks

```swift
case "create_reminder":
    let title = toolCall.args["title"] as? String ?? ""
    let dueDate = parseDate(toolCall.args["due_date"] as? String) ?? Date()
    
    // ✅ ALWAYS create reminders (removed settings check)
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
```

**EventKitManager Implementation**:
```swift
func createReminder(title: String, dueDate: Date, notes: String?) async -> String? {
    // ✅ Check authorization first
    let status = EKEventStore.authorizationStatus(for: .reminder)
    guard status == .fullAccess || status == .authorized else {
        print("❌ EventKitManager: No reminders access!")
        return nil
    }
    
    // ✅ Verify default calendar exists
    guard let calendar = eventStore.defaultCalendarForNewReminders() else {
        print("❌ EventKitManager: No default reminders calendar available")
        return nil
    }
    
    let reminder = EKReminder(eventStore: eventStore)
    reminder.title = title
    reminder.notes = notes
    reminder.calendar = calendar
    
    // ✅ Use dateComponents for due date
    let dueDateComponents = Calendar.current.dateComponents(
        [.year, .month, .day, .hour, .minute], 
        from: dueDate
    )
    reminder.dueDateComponents = dueDateComponents
    
    do {
        try eventStore.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    } catch {
        print("❌ Failed to create reminder: \(error.localizedDescription)")
        return nil
    }
}
```

**Important Note**: iOS does NOT support deep linking to specific reminders. The `x-apple-reminderkit://` URL scheme only opens the app, not individual reminders.

---

## 4. Journal View & Edit

### Problem
1. Initially: Could see journal but couldn't scroll
2. After attempted fix: Black screen, couldn't see anything
3. After revert: Could see but edit mode showed blank screen

### Root Cause
1. Disabled `TextEditor` doesn't scroll well
2. Attempted `ScrollView + Text` broke layout
3. `editedContent` was empty string when entering edit mode

### Solution
**File**: `Views/JournalView.swift`

**Key Technology**: SwiftUI `TextEditor` with state management

```swift
struct JournalDetailView: View {
    let file: JournalFile
    @State private var content: String = ""
    @State private var editedContent: String = ""
    @State private var isEditing: Bool = false
    @State private var showingSaveConfirmation: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                // ✅ Editable TextEditor with editedContent
                TextEditor(text: $editedContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // ✅ Read-only TextEditor with constant binding
                TextEditor(text: .constant(content))
                    .font(.system(.body, design: .monospaced))
                    .disabled(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isEditing {
                    Button("Save") {
                        saveContent()
                    }
                } else {
                    Button("Edit") {
                        // ✅ CRITICAL: Copy content to editedContent BEFORE entering edit mode
                        editedContent = content
                        isEditing = true
                    }
                }
            }
            if isEditing {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isEditing = false
                        loadContent()
                    }
                }
            }
        }
        .onAppear {
            loadContent()
        }
    }
    
    private func loadContent() {
        if let fileContent = try? String(contentsOf: file.url) {
            content = fileContent
        } else {
            content = "Failed to load journal content"
        }
    }
    
    private func saveContent() {
        do {
            // ✅ Save editedContent, not content
            try editedContent.write(to: file.url, atomically: true, encoding: .utf8)
            // ✅ Update content with saved changes
            content = editedContent
            isEditing = false
            showingSaveConfirmation = true
        } catch {
            print("Failed to save: \(error)")
        }
    }
}
```

**Why This Works**:
- **View Mode**: Shows `content` in disabled TextEditor (readable, limited scrolling)
- **Edit Mode**: Shows `editedContent` in editable TextEditor (fully scrollable)
- **State Flow**: 
  1. Load file → `content`
  2. Tap Edit → Copy `content` to `editedContent`
  3. Edit → Modify `editedContent`
  4. Save → Write `editedContent` to file, update `content`
  5. Cancel → Discard `editedContent`, keep `content`

**Critical**: Must copy `content` to `editedContent` BEFORE setting `isEditing = true`, otherwise TextEditor shows empty string.

---

## 5. Claude Context & Rescheduling

### Problem
When user said "meeting with Marco rescheduled to tomorrow", Claude created event at 2pm instead of using the original 10am time.

### Root Cause
Claude wasn't reading the calendar events provided in the context.

### Solution
**File**: `Services/ClaudeService.swift`

**Key Technology**: Anthropic Claude API with detailed system prompts

```swift
// In buildSystemPrompt():

## ⚠️ CRITICAL RESCHEDULING RULE - READ THIS CAREFULLY:
**When user says a meeting/event is rescheduled (e.g., "meeting with Marco rescheduled to tomorrow"):**

**EXAMPLE:**
User says: "Meeting with Marco rescheduled to tomorrow"
You see in calendar events: "Meeting with Marco on 11/16/2025 at 10:00 AM"
You MUST:
- Extract the time: 10:00 AM
- Create new event tomorrow at 10:00 AM (NOT 2pm!)
- Say: "I found your original meeting with Marco was at 10:00 AM, so I've rescheduled it to tomorrow at 10:00 AM"

**STEPS (MANDATORY):**
1. **LOOK** at the "Recent Calendar Events" and "Upcoming Calendar Events" sections I provided above
2. **SEARCH** for events matching the person's name (Marco, Marko, etc. - be flexible with spelling)
3. **EXTRACT** the exact TIME from that event (e.g., "10:00 AM", "3:30 PM")
4. **USE** that SAME TIME for the new date
5. **CREATE** both calendar event AND reminder with that time
6. **SAY** in your response: "I found the original meeting was at [TIME], so I've rescheduled it to [NEW DATE] at [SAME TIME]"
7. If NO matching event found, ONLY THEN use 2pm as default
```

**Calendar Events in Context**:
```swift
// Add upcoming calendar events
if !context.upcomingEvents.isEmpty {
    prompt += "\n## Upcoming Calendar Events (REFERENCE THESE FOR RESCHEDULING)\n"
    for event in context.upcomingEvents.prefix(20) {
        let startStr = dateFormatter.string(from: event.startDate)
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let timeStr = timeFormatter.string(from: event.startDate)
        // ✅ Show both date AND time separately for clarity
        prompt += "- **\(event.title ?? "Untitled")** on \(startStr) at \(timeStr)"
        if let location = event.location {
            prompt += " (Location: \(location))"
        }
        prompt += "\n"
    }
    prompt += "\n"
}

// Add recent calendar events
if !context.recentEvents.isEmpty {
    prompt += "\n## Recent Calendar Events (REFERENCE THESE FOR RESCHEDULING)\n"
    for event in context.recentEvents.prefix(10) {
        let startStr = dateFormatter.string(from: event.startDate)
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        let timeStr = timeFormatter.string(from: event.startDate)
        // ✅ Show both date AND time separately
        prompt += "- **\(event.title ?? "Untitled")** on \(startStr) at \(timeStr)\n"
    }
    prompt += "\n"
}
```

**Why This Works**:
- Concrete example shows Claude exactly what to do
- Time is shown separately from date for easy extraction
- Explicit numbered steps make it clear
- "REFERENCE THESE FOR RESCHEDULING" in section headers
- Claude must acknowledge finding the original time in response

**Result**: Claude now correctly finds "Meeting with Marco on 11/16/2025 at 10:00 AM" and reschedules to tomorrow at 10:00 AM.

---

## 6. Tasks View UI

### Problem
Excessive spacing between filter buttons, title, and task list consumed too much screen space.

### Solution
**File**: `Views/TasksView.swift`

**Key Technology**: SwiftUI spacing and layout modifiers

```swift
var body: some View {
    NavigationView {
        VStack(spacing: 0) {  // ✅ Zero spacing between major sections
            // Filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {  // ✅ Compact spacing between chips
                    // Status filters
                    ForEach(TaskStatus.allCases, id: \.self) { status in
                        FilterChip(
                            title: status.rawValue.capitalized,
                            isSelected: selectedStatus == status,
                            action: { selectedStatus = status }
                        )
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Company filters
                    FilterChip(
                        title: "All Companies",
                        isSelected: selectedCompany == nil,
                        action: { selectedCompany = nil }
                    )
                    
                    ForEach(companies, id: \.self) { company in
                        FilterChip(
                            title: company,
                            isSelected: selectedCompany == company,
                            action: { selectedCompany = company }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)  // ✅ Minimal vertical padding
            }
            
            Divider()
            
            // Tasks list
            List {
                ForEach(filteredTasks) { task in
                    NavigationLink(destination: TaskDetailView(task: task)) {
                        TaskRow(task: task)
                    }
                }
            }
            .listStyle(.plain)
        }
        .navigationTitle("Tasks")
        .navigationBarTitleDisplayMode(.inline)  // ✅ Inline mode saves space
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddTask = true }) {
                    Image(systemName: "plus")
                }
            }
        }
    }
}
```

**TaskDetailView** (opened from NavigationLink):
```swift
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
                
                // Status with toggle button
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
                
                // Description, assignee, company, due date...
                // (Full implementation in TasksView.swift lines 247-337)
            }
            .padding()
        }
        .navigationTitle("Task Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

**Why This Works**:
- `VStack(spacing: 0)` removes gaps between sections
- `.navigationBarTitleDisplayMode(.inline)` uses compact title
- Minimal padding on filter chips (8pt vertical)
- `NavigationLink` properly navigates to detail view
- TaskDetailView shows all task info with toggle button

---

## Key Technologies Summary

### SwiftUI Patterns
1. **`sheet(item:)`** - For showing sheets with data binding
2. **`TextEditor`** - For displaying and editing large text
3. **`NavigationLink`** - For navigating between views
4. **`.environmentObject()`** - For passing AppState down view hierarchy
5. **State management** - `@State`, `@EnvironmentObject`, `@Environment`

### iOS Frameworks
1. **EventKit** - `EKEventStore`, `EKEvent`, `EKReminder`
2. **URL Schemes** - `calshow:`, `x-apple-reminderkit://`
3. **Date Handling** - `timeIntervalSinceReferenceDate`, `DateComponents`

### API Integration
1. **Anthropic Claude API** - System prompts with examples
2. **Tool Calling** - Structured function calls from Claude
3. **Context Management** - Providing calendar/task data to Claude

### File Operations
1. **String(contentsOf:)** - Reading file contents
2. **String.write(to:)** - Writing file contents
3. **URL** - File system URLs

---

## Testing Checklist

To verify everything is working:

- [ ] **Task Attachments**: Tap task in chat → Opens detail sheet with full task info
- [ ] **Calendar Events**: Tap calendar event → Opens Calendar app to correct date/time
- [ ] **Reminders**: Created in iOS Reminders app (tap opens app)
- [ ] **Journal View**: Can see content when viewing
- [ ] **Journal Edit**: Tap Edit → See full content, can scroll and edit
- [ ] **Journal Save**: Edit content → Save → Changes persist
- [ ] **Claude Rescheduling**: "Meeting with X rescheduled to tomorrow" → Uses original time
- [ ] **Tasks View**: Compact layout, filters work, tasks tappable

---

## Common Issues & Solutions

### Task Sheet Shows Blank
**Symptom**: Tapping task shows empty sheet  
**Cause**: Using `sheet(isPresented:)` instead of `sheet(item:)`  
**Fix**: Use `sheet(item: $selectedTask) { task in ... }`

### Calendar Opens Wrong Date
**Symptom**: Opens to December 31, 2000  
**Cause**: Using event ID instead of timeIntervalSinceReferenceDate  
**Fix**: Store `start.timeIntervalSinceReferenceDate` in actionData

### Journal Edit Shows Blank
**Symptom**: Edit mode shows empty screen  
**Cause**: `editedContent` not populated when entering edit mode  
**Fix**: Set `editedContent = content` before `isEditing = true`

### Claude Ignores Calendar Context
**Symptom**: Creates events at 2pm instead of original time  
**Cause**: Prompt not explicit enough  
**Fix**: Add concrete example and numbered steps in system prompt

### Reminders Not Created
**Symptom**: No reminders appear in iOS Reminders app  
**Cause**: Settings check preventing creation  
**Fix**: Remove `if settings.autoAddToCalendar` check, always create

---

## File Locations

All modified files in this working state:

```
TenX/
├── Views/
│   ├── ChatView.swift          # Task attachments, calendar/reminder taps
│   ├── TasksView.swift         # Tasks UI, TaskDetailView
│   └── JournalView.swift       # Journal view and edit
├── Models/
│   └── AppState.swift          # Tool execution, attachment creation
├── Services/
│   ├── ClaudeService.swift     # System prompt, rescheduling rules
│   └── EventKitManager.swift   # Calendar and reminder creation
└── WORKING_STATE_ONE.md        # This document
```

---

## Restoration Steps

If something breaks, follow these steps:

1. **Identify the broken feature** using the Testing Checklist
2. **Find the relevant section** in this document
3. **Compare your code** to the code snippets provided
4. **Look for the ✅ CRITICAL comments** - these are the key parts
5. **Verify the "Why This Works" explanation** matches your understanding
6. **Test the specific feature** after making changes

---

**Last Updated**: November 16, 2025  
**Version**: 1.0  
**Status**: ✅ Production Ready
