# Working State Two - People Tracking & Chat Intelligence

**Date**: November 16, 2025  
**Status**: ✅ All Features Working + People Tracking System Complete

This document describes the complete implementation of the People Tracking System and all chat intelligence improvements. Use this as a reference to restore functionality.

**Previous State**: See [WORKING_STATE_ONE.md](./WORKING_STATE_ONE.md) for Task Attachments, Calendar Deep Links, Reminders, Journal View, and Claude Rescheduling.

**Future Work**: See [VERSION_2_IMPLEMENTATION_PLAN.md](../VERSION_2_IMPLEMENTATION_PLAN.md) for Phase 2 automation and Phase 3 iOS integrations.

---

## Table of Contents
1. [People Tracking System](#1-people-tracking-system)
2. [Rate Limit Protection](#2-rate-limit-protection)
3. [Person File Tool Integration](#3-person-file-tool-integration)
4. [Smart Chat Titles](#4-smart-chat-titles)
5. [Claude Focus Management](#5-claude-focus-management)
6. [Attachment Display Fixes](#6-attachment-display-fixes)

---

## 1. People Tracking System

### Problem
Extract all people from journal (100k+ chars), track interactions, generate AI summaries, handle rate limits, update (don't overwrite) data, show live progress.

### Solution - Journal Chunking (10k chars)

**File**: `Services/SuperHousekeepingService.swift`

```swift
private func extractPeopleFromJournal() async -> ExtractionResult {
    let chunkSize = 10_000  // ✅ Stay under rate limit
    var offset = 0
    
    while offset < journalContent.count {
        let chunk = String(journalContent[startIdx..<endIdx])
        onProgress?("📖 Processing chunk \(offset/1000)k...")
        
        // Ask Claude for names only (cheap)
        let names = try? await claudeService.extractPeopleNames(from: chunk)
        allPeople.formUnion(names)
        
        // ✅ 2-second delay to avoid rate limits
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        offset += chunkSize
    }
    
    // Extract interactions locally with regex (no API calls)
    for personName in allPeople {
        let interactions = extractInteractionsForPerson(personName, from: journalContent)
        peopleManager.addInteraction(to: personName, interaction: interaction)
    }
}
```

**Local Interaction Extraction**:
```swift
// ✅ Use word boundary regex to avoid false matches
let pattern = "\\b\(NSRegularExpression.escapedPattern(for: name))\\b"
// Extract date: (\d{4}-\d{2}-\d{2})
// Extract time: (\d{2}:\d{2})
// Classify type from keywords: meeting, call, message, email, note
```

**AI Summary Generation**:
```swift
for person in allPeople {
    // ✅ Skip people without interactions
    if person.interactions.isEmpty { continue }
    
    // ✅ Check for broken summaries (contains XML or "I need to")
    if let summary = person.summary, !isBroken(summary) { continue }
    
    let prompt = """
    CRITICAL: Respond ONLY with text. Do NOT use tools.
    Write 2-3 sentence summary of \(person.name):
    \(recentInteractions)
    """
    
    let summary = try await claudeService.generateSummary(prompt: prompt)
    
    // ✅ Clean any tool call artifacts
    let cleaned = summary.replacingOccurrences(of: "<function_call>", with: "")
    peopleManager.updatePersonSummary(name: person.name, summary: cleaned)
    
    // ✅ 2-second delay between summaries
    try? await Task.sleep(nanoseconds: 2_000_000_000)
}
```

**Person Data Management** (`PeopleManager.swift`):
```swift
func getOrCreatePerson(name: String) -> Person {
    // ✅ Never loses existing data
    if let existing = loadPerson(name: name) { return existing }
    return Person(name: name)
}

func addInteraction(to personName: String, interaction: PersonInteraction) {
    var person = getOrCreatePerson(name: personName)
    // ✅ Check for duplicates
    if !isDuplicate { person.interactions.append(interaction) }
}
```

**Live Progress UI** (`SuperHousekeepingView.swift`):
```swift
service.onProgress = { message in
    Task { @MainActor in
        self.progressMessage = message
        self.progressLog.append(message)
    }
}
```

---

## 2. Rate Limit Protection

### Problem
Claude API rate limits (30k tokens/min) caused failures during person summaries.

### Solution - Retry with Exponential Backoff

**File**: `Services/ClaudeService.swift`

```swift
func sendMessage(...) async throws -> ClaudeResponse {
    var attempt = 0
    let maxAttempts = 3
    
    while attempt < maxAttempts {
        do {
            return try await attemptSendMessage(...)
        } catch ClaudeError.apiError(let errorMessage) {
            if errorMessage.contains("rate_limit_error") {
                attempt += 1
                let waitTime = attempt * 3  // 3, 6, 9 seconds
                print("⏸️  Rate limit hit - waiting \(waitTime) seconds...")
                try? await Task.sleep(nanoseconds: UInt64(waitTime) * 1_000_000_000)
            } else {
                throw error
            }
        }
    }
}
```

**Console Output**: `⏸️  Rate limit hit - waiting 3 seconds before retry 1/3...`

---

## 3. Person File Tool Integration

### Problem
Claude called `read_person_file` but said "no information" because data wasn't sent back.

### Solution - Send Person Data in Tool Results

**Tool Definition** (`ClaudeModels.swift`):
```swift
[
    "name": "read_person_file",
    "description": "Reads person info. Use this to get context about someone.",
    "input_schema": [
        "properties": ["name": ["type": "string"]],
        "required": ["name"]
    ]
]
```

**Tool Execution** (`AppState.swift`):
```swift
case "read_person_file":
    let person = peopleManager.loadPerson(name: name)
    let markdown = peopleManager.exportPersonToMarkdown(person)
    return MessageAttachment(
        type: .task,
        title: "Person: \(name)",
        actionData: markdown  // ✅ Full person data
    )
```

**✅ CRITICAL - Send Data Back**:
```swift
// In tool result handling:
else if toolCall.name == "read_person_file" {
    let personData = attachment.actionData as? String
    toolResultsMessage += "👤 Person file for \(name):\n\n\(personData)\n\n"
}
```

**System Prompt** (`ClaudeService.swift`):
```swift
**🔥 CRITICAL: When user asks about a person:**
1. **ALWAYS call `read_person_file` FIRST**
2. **ONLY if not enough info**, then read journal
3. **Combine both sources**
```

---

## 4. Smart Chat Titles

### Problem
Title stuck as first question: "What do you know about TX2?"

### Solution - Extract Person Names, Update Dynamically

**File**: `Models/AppState.swift`

```swift
if session.messages.count == 1 {
    session.title = generateChatTitle(from: text)
} else if session.messages.count % 4 == 0 {
    // Every 4 messages, update title
    let recent = session.messages.suffix(6).map { $0.content }.joined()
    session.title = generateChatTitle(from: recent)
}

private func generateChatTitle(from text: String) -> String {
    var title = text
    // ✅ Remove question patterns
    title = title.replacingOccurrences(of: "What do you know about ", with: "")
    title = title.replacingOccurrences(of: "?", with: "")
    
    // ✅ Extract person names
    let peopleNames = peopleManager.loadAllPeople().map { $0.name }
    let mentioned = peopleNames.filter { title.contains($0) }
    
    if mentioned.count == 1 { title = mentioned[0] }
    else if mentioned.count == 2 { title = "\(mentioned[0]) & \(mentioned[1])" }
    else if mentioned.count > 2 { title = "\(mentioned[0]) & \(mentioned.count - 1) others" }
    
    return String(title.prefix(40))
}
```

**Examples**:
- "What do you know about TX2?" → "TX2"
- Ask about Nick next → "TX2 & Nick"

---

## 5. Claude Focus Management

### Problem
Asked about Nick, Claude kept talking about TX2. Said "TLDR" → got TX2 summary instead of Nick.

### Solution - Explicit Priority Instructions

**File**: `Services/ClaudeService.swift`

```swift
## Your Core Responsibilities:

1. **Focus on the MOST RECENT Question**: Always respond to what user JUST asked, not previous topics. If they ask about "Nick" after "TX2", talk about Nick.
2. **Maintain Conversation Context**: Reference earlier topics naturally, but prioritize current request

**CRITICAL - Follow-up Questions:**
If user asks "TLDR" or "summarize" after asking about someone:
- Summarize the MOST RECENT person discussed
- Example: Asked about TX2, then Nick, then "TLDR" → Summarize Nick, NOT TX2
```

---

## 6. Attachment Display Fixes

### Problem
Person files/search results tried to open as tasks → UUID parsing spam.

### Solution - Early Return for Informational Attachments

**File**: `Views/ChatView.swift`

```swift
private func handleAttachmentTap() {
    switch attachment.type {
    case .task:
        // ✅ Check if informational, not clickable
        if attachment.title.starts(with: "Person:") || 
           attachment.title.contains("Search Results") {
            print("ℹ️  Informational attachment")
            return
        }
        
        // Only try UUID parsing for real tasks
        if let taskId = UUID(uuidString: attachment.actionData) {
            selectedTask = task
        }
    }
}
```

---

## Testing Checklist

**People Tracking**:
- [ ] Run Super Housekeeping → Extracts all people
- [ ] Check People tab → Shows interactions and summaries
- [ ] Progress updates → See "Processing chunk X"
- [ ] No rate limits → Completes without errors
- [ ] Re-run safe → Updates data, no duplicates

**Chat Intelligence**:
- [ ] Ask "What do you know about TX2?" → Claude calls `read_person_file` first
- [ ] Response shows actual interactions and summary
- [ ] Ask about Nick → Claude talks about Nick, not TX2
- [ ] Say "TLDR" → Summarizes Nick (most recent)
- [ ] Chat title → "TX2 & Nick" (not stuck as first question)
- [ ] No UUID errors → Informational attachments don't try to parse

---

## Key Files Modified

```
TenX/
├── Services/
│   ├── SuperHousekeepingService.swift  # Journal chunking, person extraction, summaries
│   ├── PeopleManager.swift             # Person data management, get/create/update
│   └── ClaudeService.swift             # Rate limit retry, system prompt updates
├── Models/
│   ├── Person.swift                    # Person, PersonInteraction models
│   ├── ClaudeModels.swift              # read_person_file tool definition
│   └── AppState.swift                  # Tool execution, person data in results, chat titles
├── Views/
│   ├── SuperHousekeepingView.swift     # Live progress UI
│   ├── ChatView.swift                  # Attachment handling fixes
│   └── PeopleView.swift                # Person list and details
└── WORKING_STATE_TWO.md                # This document
```

---

## Future Work

See `VERSION_2_IMPLEMENTATION_PLAN.md` for upcoming features:
- **Phase 2**: Daily automation (auto-run housekeeping, daily summaries)
- **Phase 3**: iOS integrations (Siri shortcuts, notifications, shared extensions)

**Current Status**: Phase 1 (Core Features) ✅ COMPLETE

---

**Last Updated**: November 16, 2025  
**Version**: 2.0  
**Status**: ✅ Production Ready
