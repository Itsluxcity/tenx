# OpsBrain - Personal Command Center

A voice-driven iOS app for managing multiple companies, tracking tasks, and maintaining detailed operational journals.

## Features

### 🎙️ Voice-First Interface
- **Push-to-talk recording**: Tap to start, tap to stop
- **Waveform visualization**: Real-time audio feedback while recording
- **OpenAI Whisper transcription**: Accurate speech-to-text
- **Edit before sending**: Review and edit transcripts before processing

### 📝 Multi-Level Journaling
- **Weekly detailed journals**: Time-stamped entries organized by day
- **Weekly summaries**: High-level overview of each week
- **Monthly summaries**: Aggregated insights from weekly summaries
- **Yearly summaries**: Big-picture annual review
- All files stored as Markdown, accessible via Files app

### ✅ Task Management
- **Automatic task extraction**: Claude identifies tasks from conversations
- **Smart due dates**: Inferred from context when not explicitly stated
- **Company/project tagging**: Organize tasks by business
- **Assignee tracking**: Know who's responsible for what
- **Overdue detection**: Visual indicators for missed deadlines

### 📅 Calendar & Reminders Integration
- **EventKit integration**: Native iOS Calendar and Reminders
- **Auto-create events**: Meetings and deadlines added to calendar
- **Follow-up reminders**: Automatic reminders for tasks
- **Confirmation mode**: Optional approval before adding items

### 🛡️ Crash Safety & Recovery
- **Incremental audio saving**: Never lose recordings
- **Utterance queue**: Pending transcripts survive crashes
- **Auto-recovery**: Resume processing on app launch
- **File versioning**: Automatic backups before modifications

### 🧠 Claude AI Integration
- **Context-aware**: Sees current week's journal, summaries, and tasks
- **Tool use**: Can create/update journals, tasks, events, and reminders
- **Multiple models**: Choose between Sonnet, Opus, or Haiku
- **Structured prompts**: Business-focused, not emotional journaling

## Architecture

```
OpsBrain/
├── Models/
│   ├── AppState.swift           # Main app state and orchestration
│   ├── ChatMessage.swift         # Chat message model
│   ├── Task.swift                # Task data model
│   ├── Utterance.swift           # Transcript utterance model
│   ├── Settings.swift            # App settings
│   └── ClaudeModels.swift        # Claude API models and tools
├── Services/
│   ├── AudioManager.swift        # Audio recording and waveform
│   ├── OpenAIService.swift       # Speech-to-text transcription
│   ├── ClaudeService.swift       # Claude API integration
│   ├── FileStorageManager.swift  # File system operations
│   ├── TaskManager.swift         # Task CRUD operations
│   └── EventKitManager.swift     # Calendar/Reminders integration
├── Views/
│   ├── ContentView.swift         # Main tab view
│   ├── ChatView.swift            # Chat interface with voice input
│   ├── TasksView.swift           # Task list and filters
│   ├── JournalView.swift         # Journal browser
│   └── SettingsView.swift        # Settings and configuration
└── OpsBrainApp.swift             # App entry point
```

## File Structure (On Device)

All files are stored in the app's Documents directory and visible in Files app:

```
On My iPhone › OpsBrain/
├── audio_raw/
│   └── 2025-11-15_10-23-45_session.m4a
├── utterances/
│   └── 2025-11-15.jsonl
├── journal/
│   ├── weeks/
│   │   ├── 2025-W46-detailed.md
│   │   └── 2025-W46-summary.md
│   ├── months/
│   │   └── 2025-11-month-summary.md
│   └── years/
│       └── 2025-year-summary.md
├── tasks/
│   ├── tasks.json
│   └── tasks-log.md
├── notes/
└── backups/
    └── 2025-W46-detailed.md__2025-11-15_14-30-22.bak
```

## Setup Instructions

### 1. Open in Xcode
1. Open `OpsBrain.xcodeproj` in Xcode
2. Select your development team in Signing & Capabilities
3. Choose a unique bundle identifier

### 2. Configure API Keys
1. Run the app on your device or simulator
2. Go to Settings tab
3. Enter your API keys:
   - **Claude API Key**: Get from https://console.anthropic.com/
   - **OpenAI API Key**: Get from https://platform.openai.com/

### 3. Grant Permissions
On first launch, the app will request:
- Microphone access (for voice recording)
- Calendar access (for creating events)
- Reminders access (for creating reminders)
- Notifications (for task alerts)

### 4. Choose Claude Model
In Settings, select your preferred Claude model:
- **Claude 3.5 Sonnet**: Best balance (recommended)
- **Claude 3 Opus**: Most capable for complex tasks
- **Claude 3 Haiku**: Fastest and most affordable

## Usage

### Recording a Voice Note
1. Tap the microphone button in the chat
2. Speak your message (pauses are fine, keep talking)
3. Tap the stop button when done
4. Review the transcript in the input field
5. Edit if needed, then tap Send

### Creating Tasks
Just mention tasks naturally in conversation:
- "Scott said he'd send the contract by Friday"
- "Need to follow up with the supplier next week"
- "Marketing team meeting tomorrow at 2pm"

Claude will:
- Extract the task
- Assign to the right person
- Set a due date
- Create a reminder

### Viewing Journals
1. Go to Journal tab
2. Select Weeks, Months, or Years
3. Tap any file to view its contents
4. All files are Markdown and editable in Files app

### Managing Tasks
1. Go to Tasks tab
2. Filter by status or company
3. Tap the circle to mark tasks complete
4. Overdue tasks show a warning icon

## Testing the Full Flow

1. **Record**: Tap mic, say "I had a call with John about the new product launch. He'll send the specs by next Monday."
2. **Transcribe**: Wait for OpenAI to transcribe (a few seconds)
3. **Review**: Edit the transcript if needed
4. **Send**: Tap the send button
5. **Claude processes**:
   - Adds entry to this week's journal
   - Creates a task for "John to send specs"
   - Sets due date to next Monday
   - Creates a reminder
6. **Verify**:
   - Check Tasks tab for the new task
   - Check Journal tab for the entry
   - Check iOS Reminders app for the reminder

## Advanced Features

### File Versioning
- Every time Claude modifies a file, a backup is created
- Backups are timestamped and stored in `/backups/`
- Use the `restore_file_version` tool to revert changes

### Crash Recovery
- If the app crashes during transcription, the audio is saved
- If Claude API fails, the transcript is queued
- On next launch, pending utterances are automatically processed

### Manual File Editing
- All journal and task files are plain text
- Edit them directly in Files app or any text editor
- Changes sync back to the app

## Troubleshooting

### Transcription Fails
- Check OpenAI API key in Settings
- Ensure internet connection
- Audio file is saved in `audio_raw/` for manual retry

### Claude Not Responding
- Check Claude API key in Settings
- Verify API quota/billing
- Check Xcode console for error messages

### Tasks Not Creating Reminders
- Grant Reminders permission in iOS Settings
- Enable "Auto-add to Calendar/Reminders" in app Settings
- Or approve manually when prompted

## Security Notes

- API keys are stored in UserDefaults (for development)
- For production, migrate to Keychain
- Never commit API keys to version control
- Files are stored locally on device only

## Requirements

- iOS 17.0 or later
- Xcode 15.0 or later
- Active internet connection for API calls
- Claude API account
- OpenAI API account

## Future Enhancements

- Embeddings-based journal search
- Multi-device sync via iCloud
- Voice activity detection (auto-stop on silence)
- Rich text formatting in journals
- Export to PDF/CSV
- Siri shortcuts integration
- Apple Watch companion app

## License

Personal use only.
