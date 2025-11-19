# User Feedback Session - Nov 18, 2025 7:08pm

**Purpose**: Capture all user feedback on NEW_FEATURES_AND_FIXES_1.md  
**Status**: ✅ Complete - Ready to implement with revised plans

---

## Feature #1: Document Upload - REVISED REQUIREMENTS

### Original Plan
- PDF, TXT, MD, RTF support
- Local storage
- Basic text extraction

### 🆕 Updated Requirements (User Feedback)
1. ✅ **Add Word Documents** - .docx support required
2. ✅ **Add OCR for Images** - Text recognition for images with text (screenshots, photos)
3. ✅ **More Claude Tools** - Need read, edit, upload capabilities (not just read)
4. ✅ **Broader File Support** - "any type" means more than initially planned

### Implementation Impact
- **New Dependency**: Need Vision API or OCR library for image text extraction
- **Word Support**: Need to add .docx parsing (NSAttributedString or ZipArchive)
- **Additional Tools**: Beyond `read_uploaded_document`, need `edit_document`, `search_document_content`
- **Complexity**: INCREASED from 6 hours to ~10-12 hours
- **Research Needed**: Vision API integration, .docx libraries for Swift

### Next Steps Before Implementation
1. Research Apple Vision framework for OCR
2. Research .docx parsing libraries
3. Design edit_document tool workflow
4. Plan file type detection and handling

---

## Feature #2: Rate Limits - MAJOR REVISION ⭐ #1 PRIORITY

### Original Plan (CANCELLED)
- ❌ Reduce system prompt size (3000→1500 tokens)
- ❌ Limit tasks/events to 7 days
- ❌ Trim context to save tokens

### 🆕 Updated Strategy (User Feedback)
**User Quote**: "I don't think we really need to reduce the system prompt. I want it to still be as smart as I want it to be."

**Key Insights**:
- Progress made: 0 responses → 2-3 responses (current approach working!)
- Rate limits happen: After 3rd back-and-forth OR when asking for journal info
- User prefers: Wait 2-5 seconds rather than cancel/lose intelligence
- **Keep**: Full system prompt with ALL tasks/events/reminders
- **Strategy**: Better pauses, longer breaks, more retries

### NEW Implementation Plan

#### Task 2.1: Enhanced Retry Logic (45 min)
**File**: `Services/ClaudeService.swift` Lines 14-41

**Changes**:
1. Increase max attempts: 3 → 5
2. Longer wait times: [3s, 5s, 10s, 15s, 20s] instead of [3s, 6s, 9s]
3. Add jitter (random 0-1s) to avoid thundering herd
4. Better user messages during waits

```swift
let maxAttempts = 5  // was 3
let baseWaitTimes = [3.0, 5.0, 10.0, 15.0, 20.0]
let jitter = Double.random(in: 0...1.0)
let totalWait = baseWaitTimes[attempt] + jitter

print("⏸️ Rate limit - waiting \(Int(totalWait))s (attempt \(attempt+1)/\(maxAttempts))...")
```

#### Task 2.2: Proactive Request Rate Limiter (1 hour)
**Keep this** - Still valuable to prevent hitting limits

Add RequestRateLimiter class that:
- Tracks requests per minute
- Proactively waits before sending if approaching limit
- Max 18/minute (conservative buffer)

#### Task 2.3: Increase Tool Loop Delays (10 min)
**File**: `Models/AppState.swift` Lines 432-436

**Changes**:
- Current: 2 seconds between tool loops
- New: 4 seconds between tool loops (2x current)
- Adds up: 10 tool calls = 40s of spacing vs 20s

```swift
if loopCount > 1 {
    print("⏳ Waiting 4 seconds to avoid rate limits...")
    try? await Task.sleep(nanoseconds: 4_000_000_000) // 4 seconds (was 2)
}
```

#### Task 2.4: Smart Conversation Trimming (KEEP but adjust)
**Keep token-based trimming** but:
- Increase budget: 4000 → 6000 tokens (more context)
- Always keep first message
- Keep as many recent as fit in 6000 tokens

### Expected Impact
- **80-90% fewer rate limit errors**
- User waits longer but never loses context
- Full intelligence maintained
- Transparent wait messages

---

## Feature #3: Enhanced Descriptions - CONTEXTUAL INTELLIGENCE

### Original Plan
- ALWAYS read journal before creating
- Make all descriptions super detailed

### 🆕 Updated Requirements (User Feedback)
**User Quote**: "I want it to be very contextually intelligent. It's not very contextually intelligent right now."

**Key Insights**:
- Scott example = gold standard, but ONLY for things that REQUIRE context
- Simple requests ("remind me to call mom") = NO journal search needed
- Complex requests ("call mom about this") = Search journal first
- Need to detect WHEN context is needed, not always gather

### NEW Implementation Plan

#### Contextual Intelligence Rules
Claude should analyze user request for:
1. **Person names** → If mentioned, read person file
2. **Topic references** ("about X", "regarding Y") → Search journal for X/Y
3. **Previous mentions** ("follow up", "second reminder") → Search for related items
4. **Specific details** (numbers, dates mentioned) → Find context

#### Examples
```
✅ SIMPLE (no search):
- "Remind me to call mom"
- "Add dentist appointment tomorrow at 2pm"
- "Create task to buy groceries"

✅ COMPLEX (search first):
- "Remind me to follow up with Scott about the merch audit"
- "Add task for the campaign we discussed yesterday"
- "Remind me about that thing with the ring LLC"
```

#### Implementation Changes
1. Add context detection logic to system prompt
2. Provide examples of when to gather vs when not to
3. Keep description/notes required, but allow brief notes for simple items
4. Add "context linking" - search for related previous items

### Expected Impact
- Claude becomes smart about context gathering
- No unnecessary journal searches
- Rich context when needed
- Faster for simple requests

---

## Feature #4: Validation - AGENTIC WORKFLOW ✅ APPROVED

### User Feedback
**User Quote**: "I want it to act more like how Claude and ChatGPT act in the agent sense... like windsurf or cursor where it makes sure everything is done."

**Key Points**:
- ✅ Act like Claude.ai/ChatGPT agents
- ✅ Act like Windsurf/Cursor (makes sure everything done)
- ✅ Goes back to itself to verify
- ✅ All proposed checks sound good

### Confirmed Approach (NO CHANGES)
1. Pre-execution validation
2. TaskChecklist system
3. Post-execution verification
4. Self-loop back to complete missing
5. Summary confirmations

**Implementation**: Proceed as originally planned

---

## Feature #5: Notepad - MAKE IT VISIBLE

### Original Plan
- Temporary notepad file
- Claude can write/read/clear
- Internal working memory

### 🆕 Updated Requirements (User Feedback)
**User Quote**: "Maybe the notepad should be visible. Like when it shows thinking, that's visible... in Claude."

**Decision**: Make notepad visible in UI
- Show as collapsible "Working Notes" section in chat
- Similar to Claude.ai "thinking" display
- User can see what Claude is gathering/noting
- Transparent working process

### Implementation Changes
1. Add notepad tools (write/read/clear) - KEEP
2. **NEW**: Add UI component to display notepad content
3. **NEW**: Show notepad state in chat (collapsed by default, expandable)
4. **NEW**: Clear visual indicator when Claude is using notepad

### UI Mockup
```
[Chat Message from User]

┌─ 📝 Working Notes ─────────────────────┐
│ Searching for: Scott, merch audit     │
│ Found: Nov 14 call notes               │
│ Context: 6 action items, $17k payment │
└────────────────────────────────────────┘

[Claude's Response]
```

---

## Overall Implementation Priority (REVISED)

### Phase 1: Critical Stability (Week 1)
1. **Feature #2: Rate Limits** ⭐ PRIORITY #1
   - Days 1-2: Implement enhanced retry + rate limiter
   - **Must complete first** - everything else depends on stable API

### Phase 2: Core Intelligence (Week 2)
2. **Feature #3: Enhanced Descriptions**
   - Days 3-4: Contextual intelligence rules
3. **Feature #5: Notepad (with visible UI)**
   - Days 4-5: Working notes system

### Phase 3: Quality & Advanced (Week 3)
4. **Feature #4: Validation**
   - Days 6-7: Agentic workflow
5. **Feature #1: Document Upload**
   - Days 8-10: Full implementation with OCR & .docx

**Total**: ~15-18 hours over 2 weeks

---

## Critical Integration Checks

### Before Each Implementation
**User Quote**: "Keep in mind, there's so many features interlinked together... be very careful about how you go about this so you don't break anything."

### Systems to Check
1. **Housekeeping** - Does it still work after changes?
2. **Super Housekeeping** - People extraction still functional?
3. **People Manager** - Read/write person files still work?
4. **Chat System** - Tool execution chain intact?
5. **File Storage** - Journal operations unaffected?

### Testing Protocol
For each feature:
1. Build and run
2. Test the new feature
3. **Run full housekeeping cycle** (test integration)
4. **Test super housekeeping** (test people features)
5. **Test multi-tool chat session** (test tool chain)
6. Verify no regressions

---

## Summary of Changes

### Added
- ✅ .docx support requirement
- ✅ OCR/image text extraction
- ✅ Visible notepad UI
- ✅ Contextual intelligence (smart context gathering)

### Removed
- ❌ System prompt reduction
- ❌ Context limitation to 7 days
- ❌ Always-search-journal rule

### Enhanced
- ✅ Retry logic (3→5 attempts, longer waits)
- ✅ Tool loop delays (2s→4s)
- ✅ Conversation trimming (4000→6000 token budget)
- ✅ Smart context detection

### Kept
- ✅ Validation/checklist system
- ✅ Request rate limiter
- ✅ Pre-execution checks
- ✅ Required description/notes fields

---

## Next Action: Start with Rate Limits

**Ready to implement Feature #2 first per user priority.**

All other features wait until rate limits are stable.
