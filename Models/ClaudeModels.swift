import Foundation
import EventKit

struct ClaudeContext {
    let currentWeekJournal: String
    let weeklySummaries: [String]
    let monthlySummary: String?
    let tasks: [TaskItem]
    let upcomingEvents: [EKEvent]
    let recentEvents: [EKEvent]
    let reminders: [EKReminder]
    let currentDate: Date
}

struct ClaudeResponse {
    let content: String
    let toolCalls: [ToolCall]
}

struct ToolCall {
    let id: String
    let name: String
    let args: [String: Any]
}

struct ClaudeTools {
    static let allTools: [[String: Any]] = [
        [
            "name": "append_to_weekly_journal",
            "description": "Appends an entry to the current week's journal. Date and time are AUTOMATICALLY set to NOW (exact current moment). Do NOT provide date or time - they are auto-generated.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "content": ["type": "string", "description": "The journal entry content. Time will be prepended automatically."]
                ],
                "required": ["content"]
            ]
        ],
        [
            "name": "delete_journal_entry",
            "description": "Deletes a specific journal entry by searching for matching content. Use when user says 'delete that journal entry' or 'undo that'.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "date": ["type": "string", "description": "Date of entry to delete (YYYY-MM-DD)"],
                    "content_match": ["type": "string", "description": "Unique text from the entry to identify it (e.g., 'Nick texted to reschedule')"]
                ],
                "required": ["date", "content_match"]
            ]
        ],
        [
            "name": "update_weekly_summary",
            "description": "Updates the weekly summary file",
            "input_schema": [
                "type": "object",
                "properties": [
                    "week_id": ["type": "string", "description": "Week identifier like 2025-W46"],
                    "summary_text": ["type": "string"],
                    "append_or_replace": ["type": "string", "enum": ["append", "replace"]]
                ],
                "required": ["week_id", "summary_text"]
            ]
        ],
        [
            "name": "update_monthly_summary",
            "description": "Updates the monthly summary file",
            "input_schema": [
                "type": "object",
                "properties": [
                    "month_id": ["type": "string", "description": "Month like 2025-11"],
                    "summary_text": ["type": "string"]
                ],
                "required": ["month_id", "summary_text"]
            ]
        ],
        [
            "name": "update_yearly_summary",
            "description": "Updates the yearly summary file",
            "input_schema": [
                "type": "object",
                "properties": [
                    "year": ["type": "string"],
                    "summary_text": ["type": "string"]
                ],
                "required": ["year", "summary_text"]
            ]
        ],
        [
            "name": "create_or_update_task",
            "description": "Creates or updates a task with details",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_id": ["type": "string"],
                    "title": ["type": "string"],
                    "description": ["type": "string"],
                    "assignee": ["type": "string"],
                    "company": ["type": "string"],
                    "due_date": ["type": "string", "description": "ISO date string"]
                ],
                "required": ["title"]
            ]
        ],
        [
            "name": "mark_task_complete",
            "description": "Marks a task as complete",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_id": ["type": "string"]
                ],
                "required": ["task_id"]
            ]
        ],
        [
            "name": "delete_task",
            "description": "Deletes a task. Use when user says 'delete that task' or 'cancel that task' or 'undo that task creation'.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_id": ["type": "string", "description": "ID of task to delete"],
                    "title_match": ["type": "string", "description": "Task title to search for if ID unknown"]
                ],
                "required": []
            ]
        ],
        [
            "name": "update_task_due_date",
            "description": "Updates the due date of a task",
            "input_schema": [
                "type": "object",
                "properties": [
                    "task_id": ["type": "string"],
                    "due_date": ["type": "string"]
                ],
                "required": ["task_id", "due_date"]
            ]
        ],
        [
            "name": "create_calendar_event",
            "description": "Creates a calendar event. Use exact title, location, and notes from original event when rescheduling.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "Event title (use EXACT original title when rescheduling)"],
                    "start": ["type": "string", "description": "ISO datetime"],
                    "end": ["type": "string", "description": "ISO datetime"],
                    "location": ["type": "string", "description": "Event location (copy from original when rescheduling)"],
                    "notes": ["type": "string", "description": "Event notes (copy from original when rescheduling)"]
                ],
                "required": ["title", "start", "end"]
            ]
        ],
        [
            "name": "update_calendar_event",
            "description": "Updates an existing calendar event. Use this to reschedule events instead of creating duplicates.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "event_title": ["type": "string", "description": "Current title of the event to find"],
                    "original_date": ["type": "string", "description": "Original date of event (YYYY-MM-DD) to help find it"],
                    "new_title": ["type": "string", "description": "New title (optional, keeps original if not provided)"],
                    "new_start": ["type": "string", "description": "New start datetime (ISO format)"],
                    "new_end": ["type": "string", "description": "New end datetime (ISO format)"],
                    "new_location": ["type": "string", "description": "New location (optional, keeps original if not provided)"],
                    "new_notes": ["type": "string", "description": "New notes (optional, keeps original if not provided)"]
                ],
                "required": ["event_title", "new_start", "new_end"]
            ]
        ],
        [
            "name": "delete_calendar_event",
            "description": "Deletes a calendar event. Use when user wants to cancel an event.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "event_title": ["type": "string", "description": "Title of the event to delete"],
                    "event_date": ["type": "string", "description": "Date of event (YYYY-MM-DD) to help find it"]
                ],
                "required": ["event_title", "event_date"]
            ]
        ],
        [
            "name": "check_availability",
            "description": "Checks calendar availability. Provide specific datetime strings to check if those times are free. If you don't have specific times to check, call it with empty array to see all upcoming events. Example with times: [\"2025-11-21T17:00:00-08:00\", \"2025-11-22T17:00:00-08:00\"]. Example without: []",
            "input_schema": [
                "type": "object",
                "properties": [
                    "proposed_times": ["type": "array", "items": ["type": "string"], "description": "Array of ISO8601 datetime strings to check. Use format '2025-11-21T17:00:00-08:00'. Leave empty [] to see all upcoming events."],
                    "duration_minutes": ["type": "integer", "description": "Duration needed in minutes (default 60)"],
                    "days_ahead": ["type": "integer", "description": "How many days ahead to check (default 7)"]
                ],
                "required": []
            ]
        ],
        [
            "name": "create_reminder",
            "description": "Creates a reminder with EXTENSIVE detail. CRITICAL: You MUST provide comprehensive notes with all relevant context.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "title": ["type": "string", "description": "Brief title for the reminder"],
                    "due_date": ["type": "string", "description": "Due date (YYYY-MM-DD)"],
                    "notes": ["type": "string", "description": "REQUIRED: Put ALL relevant context here. Include: why this reminder exists, who's involved, what's been discussed, any deadlines, dependencies, or background. Be VERY detailed. Minimum 2-3 complete sentences. Example: 'Follow up with Tommy about merch breakdown. He was supposed to send this last week but still hasn't. This is blocking the campaign launch scheduled for Nov 25. Need final numbers to place bulk order with supplier.'"]
                ],
                "required": ["title", "due_date", "notes"]
            ]
        ],
        [
            "name": "restore_file_version",
            "description": "Restores a file from backup",
            "input_schema": [
                "type": "object",
                "properties": [
                    "file_path": ["type": "string"],
                    "version_timestamp": ["type": "string"]
                ],
                "required": ["file_path", "version_timestamp"]
            ]
        ],
        [
            "name": "read_journal",
            "description": "Reads the current week's journal in chunks to avoid rate limits. The journal may be very large (100k+ chars), so read it in 5000 char chunks. Call multiple times with increasing offset to read the whole journal.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "offset": ["type": "integer", "description": "Character offset to start reading from (default 0)"],
                    "chunk_size": ["type": "integer", "description": "Number of characters to read (default 5000, max 10000)"]
                ],
                "required": []
            ]
        ],
        [
            "name": "search_journal",
            "description": "Search the current week's journal for specific content. Returns match count with snippets showing context. Use when you want to see WHERE information appears.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Text to search for in the journal"]
                ],
                "required": ["query"]
            ]
        ],
        [
            "name": "get_relevant_journal_context",
            "description": "🔍 EFFICIENT SEARCH: Get all relevant journal sections matching your search query in ONE response. Use when user asks to FIND/SEARCH information. Returns up to 20k chars of context. Much faster than multiple read_journal calls!",
            "input_schema": [
                "type": "object",
                "properties": [
                    "search_query": ["type": "string", "description": "What to search for (e.g., 'Scott Ring LLC consolidation' or 'Tommy merch')"],
                    "max_chars": ["type": "integer", "description": "Max characters to return (default: 20000)"]
                ],
                "required": ["search_query"]
            ]
        ],
        [
            "name": "read_person_file",
            "description": "Read information about a specific person from their person file",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Person's name"]
                ],
                "required": ["name"]
            ]
        ],
        [
            "name": "add_person_interaction",
            "description": "Add an interaction to a person's file",
            "input_schema": [
                "type": "object",
                "properties": [
                    "name": ["type": "string", "description": "Person's name"],
                    "date": ["type": "string", "description": "Date of interaction (YYYY-MM-DD)"],
                    "time": ["type": "string", "description": "Time of interaction (HH:MM)"],
                    "content": ["type": "string", "description": "What was discussed/done"],
                    "type": ["type": "string", "description": "Type: meeting, call, message, email, or note"]
                ],
                "required": ["name", "content"]
            ]
        ],
        // TASK 5.2: Notepad Tools for Working Memory
        [
            "name": "write_to_notepad",
            "description": "Write to your temporary working notepad. Use this to store intermediate findings, context gathered, or information you want to remember while working on a multi-step task. Perfect for accumulating information across tool calls before creating something.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "content": ["type": "string", "description": "What to write to the notepad"],
                    "mode": ["type": "string", "enum": ["append", "replace"], "description": "append: Add to existing content (default). replace: Replace all content"]
                ],
                "required": ["content"]
            ]
        ],
        [
            "name": "read_notepad",
            "description": "Read your current notepad content. Use this to recall what you've stored in previous steps and review your accumulated findings before proceeding.",
            "input_schema": [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ],
        [
            "name": "clear_notepad",
            "description": "Clear the notepad. Use when starting a fresh task or when stored information is no longer needed.",
            "input_schema": [
                "type": "object",
                "properties": [:],
                "required": []
            ]
        ]
    ]
}
