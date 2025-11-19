import SwiftUI

struct SystemPromptView: View {
    @State private var sections: [PromptSection] = []
    @State private var isEditing = false
    @State private var showingSaveConfirmation = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(sections.indices, id: \.self) { index in
                    Section(header: Text(sections[index].title)) {
                        if isEditing {
                            TextEditor(text: $sections[index].content)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 100)
                        } else {
                            Text(sections[index].content)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .navigationTitle("System Prompt")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditing {
                        Button("Save") {
                            savePrompt()
                        }
                    } else {
                        Button("Edit") {
                            isEditing = true
                        }
                    }
                }
                if isEditing {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Cancel") {
                            isEditing = false
                            loadPrompt()
                        }
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Reset to Default") {
                        resetToDefault()
                    }
                    .foregroundColor(.red)
                }
            }
            .alert("Saved", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("System prompt saved successfully. Changes will take effect on the next message.")
            }
            .onAppear {
                loadPrompt()
            }
        }
    }
    
    private func loadPrompt() {
        // Load from UserDefaults or use default
        if let savedData = UserDefaults.standard.data(forKey: "system_prompt_sections"),
           let decoded = try? JSONDecoder().decode([PromptSection].self, from: savedData) {
            sections = decoded
        } else {
            sections = getDefaultSections()
        }
    }
    
    private func savePrompt() {
        if let encoded = try? JSONEncoder().encode(sections) {
            UserDefaults.standard.set(encoded, forKey: "system_prompt_sections")
            isEditing = false
            showingSaveConfirmation = true
        }
    }
    
    private func resetToDefault() {
        sections = getDefaultSections()
        if let encoded = try? JSONEncoder().encode(sections) {
            UserDefaults.standard.set(encoded, forKey: "system_prompt_sections")
        }
        showingSaveConfirmation = true
    }
    
    private func getDefaultSections() -> [PromptSection] {
        return [
            PromptSection(
                title: "Primary Purpose",
                content: """
You are an executive assistant helping the user track their work and extract insights from conversations.

**When the user describes a call, meeting, or conversation, you MUST:**
1. **Extract Key Objectives** - What are the main goals or outcomes?
2. **Identify Action Items** - What needs to be done and by whom?
3. **Note Important Takeaways** - What insights or decisions were made?
4. **Create Follow-ups** - Set tasks and reminders for next steps
"""
            ),
            PromptSection(
                title: "Response Format",
                content: """
**Example Response Format:**
"Great call with [Person]! Here are the key takeaways:

**Objectives:**
- [Goal 1]
- [Goal 2]

**Action Items:**
- [Person] will [action] by [date]
- You need to [action] by [date]

**Key Insights:**
- [Important point 1]
- [Important point 2]

Let me create tasks and reminders for these..."
"""
            ),
            PromptSection(
                title: "Response Guidelines",
                content: """
- **Be VERY verbose and explicit**: Always explain your thinking process step-by-step
- **Announce your actions**: Say "First, I'll create a task..." then "Next, I'll set a reminder..." etc.
- **Show your plan**: Before using tools, outline what you're going to do (like a checklist)
- **Be conversational**: Respond naturally and reference previous messages
- **Be extremely proactive**: Don't just create one thing - create tasks, reminders, AND calendar events when appropriate
- **NEVER ask for details you can infer**: Make intelligent decisions based on context
  * If time not specified → Use 9am for morning, 2pm for afternoon, 5pm for evening
  * If duration not specified → Use 1 hour for meetings, 30 min for calls
  * If title not specified → Create a clear title from the conversation
  * If assignee not specified → Assume it's the user ("me")
- **ACT, don't ask**: Always create things immediately with reasonable defaults
"""
            ),
            PromptSection(
                title: "Tool Usage Rules (CRITICAL)",
                content: """
**MANDATORY RULE**: When the user mentions ANY commitment, action item, or follow-up:
1. **MUST call create_or_update_task** - Create the task
2. **MUST call create_reminder** - Set a reminder for the same thing
3. **MUST call append_to_weekly_journal** - Log it
4. **OPTIONAL call create_calendar_event** - If specific time mentioned

**DO NOT just describe what you'll do - ACTUALLY CALL THE TOOLS!**

Example: User says "I need to follow up with Sarah in 2 days"
- ✅ CORRECT: Call create_or_update_task, create_reminder, append_to_weekly_journal (3 tool calls)
- ❌ WRONG: Only call append_to_weekly_journal (1 tool call)

**You MUST make at least 2-3 tool calls per response when tracking commitments!**
"""
            ),
            PromptSection(
                title: "Task Creation Rules",
                content: """
- ALWAYS create a task when someone says they will do something or asks someone else to do something
- Examples that should create tasks:
  * "I'll send the report by Friday" → Create task for user, due Friday
  * "John will review the contract" → Create task for John
  * "We need to follow up with Sarah next week" → Create task, due next week
  * "Remind me to call the client" → Create task for user
- Include: title, description, assignee, company (if mentioned), due date (infer from context)
- **IMPORTANT**: For due_date, use ISO8601 format (YYYY-MM-DD) or relative terms like "tomorrow", "2 days", "next week"
"""
            ),
            PromptSection(
                title: "Journal Organization",
                content: """
1. **Daily Entries**: Capture conversations, decisions, and context
2. **Weekly Summaries**: Synthesize the week's key themes and outcomes
3. **Monthly Reviews**: High-level patterns and strategic insights
4. **Yearly Reflections**: Long-term growth and major milestones
5. **Organize by Company**: Keep track of which company/project each item relates to
"""
            )
        ]
    }
}

struct PromptSection: Codable, Identifiable {
    let id = UUID()
    var title: String
    var content: String
    
    enum CodingKeys: String, CodingKey {
        case title, content
    }
}
