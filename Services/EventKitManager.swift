import EventKit
import Foundation

class EventKitManager {
    private let eventStore = EKEventStore()
    
    func requestCalendarAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToEvents()
            } catch {
                print("Calendar access request failed: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .event) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    func requestRemindersAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            do {
                return try await eventStore.requestFullAccessToReminders()
            } catch {
                print("Reminders access request failed: \(error)")
                return false
            }
        } else {
            return await withCheckedContinuation { continuation in
                eventStore.requestAccess(to: .reminder) { granted, _ in
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    func createEvent(title: String, start: Date, end: Date, location: String? = nil, notes: String?) async -> String? {
        // Check authorization
        let status = EKEventStore.authorizationStatus(for: .event)
        print("📅 Calendar authorization status: \(status.rawValue)")
        
        guard status == .fullAccess || status == .authorized else {
            print("❌ EventKitManager: No calendar access! Status: \(status.rawValue)")
            return nil
        }
        
        guard let calendar = eventStore.defaultCalendarForNewEvents else {
            print("❌ EventKitManager: No default calendar available")
            return nil
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = start
        event.endDate = end
        event.location = location
        event.notes = notes
        event.calendar = calendar
        
        do {
            try eventStore.save(event, span: .thisEvent)
            print("✅ EventKitManager: Created calendar event '\(title)' at \(start) with ID: \(event.eventIdentifier ?? "nil")")
            return event.eventIdentifier
        } catch {
            print("❌ EventKitManager: Failed to create event '\(title)': \(error.localizedDescription)")
            return nil
        }
    }
    
    func createReminder(title: String, dueDate: Date, notes: String?) async -> String? {
        // Check authorization
        let status = EKEventStore.authorizationStatus(for: .reminder)
        print("🔔 Reminders authorization status: \(status.rawValue)")
        
        guard status == .fullAccess || status == .authorized else {
            print("❌ EventKitManager: No reminders access! Status: \(status.rawValue)")
            return nil
        }
        
        guard let calendar = eventStore.defaultCalendarForNewReminders() else {
            print("❌ EventKitManager: No default reminders calendar available")
            return nil
        }
        
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = calendar
        
        let dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        reminder.dueDateComponents = dueDateComponents
        
        do {
            try eventStore.save(reminder, commit: true)
            print("✅ EventKitManager: Created reminder '\(title)' due \(dueDate) with ID: \(reminder.calendarItemIdentifier)")
            return reminder.calendarItemIdentifier
        } catch {
            print("❌ EventKitManager: Failed to create reminder '\(title)': \(error.localizedDescription)")
            return nil
        }
    }
    
    func fetchUpcomingEvents(daysAhead: Int = 30) -> [EKEvent] {
        let startDate = Date()
        let endDate = Calendar.current.date(byAdding: .day, value: daysAhead, to: startDate) ?? startDate
        
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        
        let events = eventStore.events(matching: predicate)
        return events.sorted { $0.startDate < $1.startDate }
    }
    
    func fetchRecentEvents(daysBehind: Int = 7) -> [EKEvent] {
        let endDate = Date()
        let startDate = Calendar.current.date(byAdding: .day, value: -daysBehind, to: endDate) ?? endDate
        
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        
        let events = eventStore.events(matching: predicate)
        return events.sorted { $0.startDate < $1.startDate }
    }
    
    func fetchReminders(includeCompleted: Bool = false) -> [EKReminder] {
        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForReminders(in: calendars)
        
        var reminders: [EKReminder] = []
        let semaphore = DispatchSemaphore(value: 0)
        
        eventStore.fetchReminders(matching: predicate) { fetchedReminders in
            if let fetchedReminders = fetchedReminders {
                reminders = includeCompleted ? fetchedReminders : fetchedReminders.filter { !$0.isCompleted }
            }
            semaphore.signal()
        }
        
        semaphore.wait()
        return reminders.sorted { ($0.dueDateComponents?.date ?? Date.distantFuture) < ($1.dueDateComponents?.date ?? Date.distantFuture) }
    }
    
    func cancelReminder(reminderId: String) async {
        guard let reminder = eventStore.calendarItem(withIdentifier: reminderId) as? EKReminder else {
            return
        }
        
        do {
            try eventStore.remove(reminder, commit: true)
            print("Cancelled reminder: \(reminderId)")
        } catch {
            print("Failed to cancel reminder: \(error)")
        }
    }
    
    func deleteEvent(_ event: EKEvent) throws {
        try eventStore.remove(event, span: .thisEvent)
    }
    
    // MARK: - Advanced Calendar Management
    
    func findEvent(title: String, nearDate: Date) -> EKEvent? {
        // Search within 7 days before and after the target date
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: nearDate) ?? nearDate
        let endDate = Calendar.current.date(byAdding: .day, value: 7, to: nearDate) ?? nearDate
        
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        let events = eventStore.events(matching: predicate)
        
        // Find event with matching title (case-insensitive)
        return events.first { event in
            event.title?.lowercased() == title.lowercased()
        }
    }
    
    func updateEvent(title: String, originalDate: Date, newTitle: String?, newStart: Date, newEnd: Date, newLocation: String?, newNotes: String?) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else {
            print("❌ EventKitManager: No calendar access for update")
            return false
        }
        
        // Find the event
        guard let event = findEvent(title: title, nearDate: originalDate) else {
            print("❌ EventKitManager: Event '\(title)' not found near \(originalDate)")
            return false
        }
        
        print("✅ Found event to update: '\(event.title ?? "")' at \(event.startDate)")
        
        // Update fields
        if let newTitle = newTitle {
            event.title = newTitle
        }
        event.startDate = newStart
        event.endDate = newEnd
        
        // Only update location/notes if provided (nil means keep existing)
        if let newLocation = newLocation {
            event.location = newLocation
        }
        if let newNotes = newNotes {
            event.notes = newNotes
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            print("✅ EventKitManager: Updated event '\(event.title ?? "")' to \(newStart)")
            return true
        } catch {
            print("❌ EventKitManager: Failed to update event: \(error.localizedDescription)")
            return false
        }
    }
    
    func deleteEventByTitle(title: String, date: Date) async -> Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess || status == .authorized else {
            print("❌ EventKitManager: No calendar access for delete")
            return false
        }
        
        // Find the event
        guard let event = findEvent(title: title, nearDate: date) else {
            print("❌ EventKitManager: Event '\(title)' not found near \(date)")
            return false
        }
        
        print("✅ Found event to delete: '\(event.title ?? "")' at \(event.startDate)")
        
        do {
            try eventStore.remove(event, span: .thisEvent)
            print("✅ EventKitManager: Deleted event '\(title)'")
            return true
        } catch {
            print("❌ EventKitManager: Failed to delete event: \(error.localizedDescription)")
            return false
        }
    }
    
    func checkAvailability(proposedTimes: [Date], durationMinutes: Int = 60) -> [String: Bool] {
        let calendars = eventStore.calendars(for: .event)
        var availability: [String: Bool] = [:]
        
        let dateFormatter = ISO8601DateFormatter()
        
        for proposedTime in proposedTimes {
            let endTime = Calendar.current.date(byAdding: .minute, value: durationMinutes, to: proposedTime) ?? proposedTime
            
            // Check for conflicts
            let predicate = eventStore.predicateForEvents(withStart: proposedTime, end: endTime, calendars: calendars)
            let conflicts = eventStore.events(matching: predicate)
            
            let isFree = conflicts.isEmpty
            let timeKey = dateFormatter.string(from: proposedTime)
            availability[timeKey] = isFree
            
            if isFree {
                print("✅ Available: \(proposedTime)")
            } else {
                print("❌ Conflict at \(proposedTime): \(conflicts.count) event(s)")
            }
        }
        
        return availability
    }
}

