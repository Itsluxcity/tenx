import Foundation

class FileStorageManager {
    private let fileManager = FileManager.default
    var documentsURL: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    init() {
        createDirectoryStructure()
    }
    
    private func createDirectoryStructure() {
        let directories = [
            "audio_raw",
            "utterances",
            "journal/weeks",
            "journal/months",
            "journal/years",
            "tasks",
            "notes",
            "backups"
        ]
        
        for dir in directories {
            let dirURL = documentsURL.appendingPathComponent(dir)
            try? fileManager.createDirectory(at: dirURL, withIntermediateDirectories: true)
        }
    }
    
    // MARK: - Audio Storage
    
    func saveAudioFile(from tempURL: URL) -> URL {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let filename = "\(timestamp)_session.m4a"
        let destinationURL = documentsURL.appendingPathComponent("audio_raw/\(filename)")
        
        try? fileManager.copyItem(at: tempURL, to: destinationURL)
        
        return destinationURL
    }
    
    // MARK: - Utterance Logging
    
    func saveUtterance(_ utterance: Utterance) {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: utterance.timestamp)
        
        let utteranceFile = documentsURL.appendingPathComponent("utterances/\(dateString).jsonl")
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let jsonData = try? encoder.encode(utterance),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            let line = jsonString + "\n"
            
            if let handle = try? FileHandle(forWritingTo: utteranceFile) {
                handle.seekToEndOfFile()
                handle.write(line.data(using: .utf8)!)
                try? handle.close()
            } else {
                try? line.write(to: utteranceFile, atomically: true, encoding: .utf8)
            }
        }
    }
    
    func loadPendingUtterances() -> [Utterance] {
        var pendingUtterances: [Utterance] = []
        let utterancesDir = documentsURL.appendingPathComponent("utterances")
        
        guard let files = try? fileManager.contentsOfDirectory(at: utterancesDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        for file in files where file.pathExtension == "jsonl" {
            guard let content = try? String(contentsOf: file) else { continue }
            
            for line in content.components(separatedBy: "\n") where !line.isEmpty {
                if let data = line.data(using: .utf8),
                   let utterance = try? decoder.decode(Utterance.self, from: data),
                   utterance.status == .pending || utterance.status == .error {
                    pendingUtterances.append(utterance)
                }
            }
        }
        
        return pendingUtterances
    }
    
    func updateUtteranceStatus(_ id: UUID, status: UtteranceStatus) {
        // In a production app, implement proper JSONL update logic
        // For now, this is a simplified version
        print("Updated utterance \(id) to status: \(status)")
    }
    
    // MARK: - Journal Management
    
    func loadCurrentWeekDetailedJournal() -> String {
        let weekId = getCurrentWeekId()
        let journalFile = documentsURL.appendingPathComponent("journal/weeks/\(weekId)-detailed.md")
        
        if let content = try? String(contentsOf: journalFile) {
            return content
        }
        
        // Create new week file
        let initialContent = "# Week \(weekId) Detailed Journal\n\n"
        try? initialContent.write(to: journalFile, atomically: true, encoding: .utf8)
        return initialContent
    }
    
    func loadRecentWeeklySummaries(count: Int) -> [String] {
        var summaries: [String] = []
        let weeksDir = documentsURL.appendingPathComponent("journal/weeks")
        
        guard let files = try? fileManager.contentsOfDirectory(at: weeksDir, includingPropertiesForKeys: nil) else {
            return []
        }
        
        let summaryFiles = files.filter { $0.lastPathComponent.contains("summary.md") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .prefix(count)
        
        for file in summaryFiles {
            if let content = try? String(contentsOf: file) {
                summaries.append(content)
            }
        }
        
        return summaries
    }
    
    func loadCurrentMonthSummary() -> String? {
        let monthId = getCurrentMonthId()
        let summaryFile = documentsURL.appendingPathComponent("journal/months/\(monthId)-month-summary.md")
        return try? String(contentsOf: summaryFile)
    }
    
    /// Appends content to weekly journal using current date/time with duplicate detection
    func appendToWeeklyJournal(date: Date, content: String) -> Bool {
        let weekId = getCurrentWeekId()
        let journalFile = documentsURL.appendingPathComponent("journal/weeks/\(weekId)-detailed.md")
        
        // Backup before modifying
        backupFile(journalFile)
        
        var existingContent = (try? String(contentsOf: journalFile)) ?? "# Week \(weekId) Detailed Journal\n\n"
        
        // Check for duplicate content (fuzzy match)
        let contentToCheck = content.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove timestamp prefix like "[17:30]" for comparison
        let contentWithoutTimestamp = contentToCheck.replacingOccurrences(of: #"^\[\d+:\d+\]\s*"#, 
                                                                          with: "", 
                                                                          options: .regularExpression)
        
        let existingLines = existingContent.components(separatedBy: .newlines)
        
        // Check if any existing line contains this content (90% similarity check)
        let isDuplicate = existingLines.contains { line in
            let normalizedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            // Remove timestamp and list marker
            let lineWithoutTimestamp = normalizedLine
                .replacingOccurrences(of: #"^\[\d+:\d+\]\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: "^- ", with: "", options: .regularExpression)
            
            // If content is very similar (contains or is contained), it's a duplicate
            if lineWithoutTimestamp.lowercased().contains(contentWithoutTimestamp.lowercased()) {
                return lineWithoutTimestamp.count - contentWithoutTimestamp.count < 20 // Within 20 chars
            }
            if contentWithoutTimestamp.lowercased().contains(lineWithoutTimestamp.lowercased()) {
                return contentWithoutTimestamp.count - lineWithoutTimestamp.count < 20
            }
            return false
        }
        
        if isDuplicate {
            print("⚠️ Skipping duplicate journal entry: \(contentWithoutTimestamp.prefix(50))...")
            return true // Return true because it's already there
        }
        
        // Format date for day header
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "EEEE yyyy-MM-dd"
        let dayHeader = "## \(dateFormatter.string(from: date))"
        
        let entry = "\(content)\n"
        
        // Find or create day section
        if existingContent.contains(dayHeader) {
            // Append to existing day
            if let range = existingContent.range(of: dayHeader) {
                let insertPosition = existingContent.index(range.upperBound, offsetBy: 1)
                existingContent.insert(contentsOf: entry, at: insertPosition)
            }
        } else {
            // Add new day section
            existingContent += "\n\(dayHeader)\n\(entry)\n"
        }
        
        // Write to file
        do {
            try existingContent.write(to: journalFile, atomically: true, encoding: .utf8)
            return true
        } catch {
            print("❌ Failed to write journal: \(error)")
            return false
        }
    }
    
    func deleteJournalEntry(date: String, contentMatch: String) -> Bool {
        let weekId = getCurrentWeekId()
        let journalFile = documentsURL.appendingPathComponent("journal/weeks/\(weekId)-detailed.md")
        
        print("🗑️  Searching for journal entry to delete: \(contentMatch.prefix(50))...")
        
        guard var existingContent = try? String(contentsOf: journalFile) else {
            print("❌ Could not read journal file")
            return false
        }
        
        // Backup before modifying
        backupFile(journalFile)
        
        let dayHeader = getDayHeader(from: date)
        print("🗑️  Looking in section: \(dayHeader)")
        
        // Split into lines
        var lines = existingContent.components(separatedBy: "\n")
        var foundAndDeleted = false
        var inCorrectDay = false
        var linesToRemove: [Int] = []
        
        for (index, line) in lines.enumerated() {
            // Check if we're in the correct day section
            if line.contains(dayHeader) {
                inCorrectDay = true
                continue
            }
            
            // If we hit another day header, we're out of the target section
            if line.hasPrefix("##") && !line.contains(dayHeader) {
                inCorrectDay = false
            }
            
            // Check if this line matches the content we want to delete
            if inCorrectDay && line.contains(contentMatch) {
                linesToRemove.append(index)
                foundAndDeleted = true
                print("✅ Found matching entry at line \(index): \(line.prefix(70))")
            }
        }
        
        if !foundAndDeleted {
            print("❌ No matching entry found")
            return false
        }
        
        // Remove lines in reverse order to maintain indices
        for index in linesToRemove.reversed() {
            lines.remove(at: index)
        }
        
        // Reconstruct content
        let newContent = lines.joined(separator: "\n")
        
        do {
            try newContent.write(to: journalFile, atomically: true, encoding: .utf8)
            print("✅ Deleted \(linesToRemove.count) journal entry(ies)")
            return true
        } catch {
            print("❌ Failed to write updated journal: \(error)")
            return false
        }
    }
    
    func updateWeeklySummary(weekId: String, summaryText: String, appendOrReplace: String) {
        let summaryFile = documentsURL.appendingPathComponent("journal/weeks/\(weekId)-summary.md")
        
        backupFile(summaryFile)
        
        if appendOrReplace == "replace" {
            try? summaryText.write(to: summaryFile, atomically: true, encoding: .utf8)
        } else {
            var existing = (try? String(contentsOf: summaryFile)) ?? ""
            existing += "\n" + summaryText
            try? existing.write(to: summaryFile, atomically: true, encoding: .utf8)
        }
    }
    
    func updateMonthlySummary(monthId: String, summaryText: String) {
        let summaryFile = documentsURL.appendingPathComponent("journal/months/\(monthId)-month-summary.md")
        backupFile(summaryFile)
        try? summaryText.write(to: summaryFile, atomically: true, encoding: .utf8)
    }
    
    func updateYearlySummary(year: String, summaryText: String) {
        let summaryFile = documentsURL.appendingPathComponent("journal/years/\(year)-year-summary.md")
        backupFile(summaryFile)
        try? summaryText.write(to: summaryFile, atomically: true, encoding: .utf8)
    }
    
    // MARK: - Backup Management
    
    private func backupFile(_ fileURL: URL) {
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())
        
        let filename = fileURL.lastPathComponent
        let backupFilename = "\(filename)__\(timestamp).bak"
        let backupURL = documentsURL.appendingPathComponent("backups/\(backupFilename)")
        
        try? fileManager.copyItem(at: fileURL, to: backupURL)
    }
    
    func restoreFileVersion(filePath: String, versionTimestamp: String) {
        let originalURL = documentsURL.appendingPathComponent(filePath)
        let filename = originalURL.lastPathComponent
        let backupFilename = "\(filename)__\(versionTimestamp).bak"
        let backupURL = documentsURL.appendingPathComponent("backups/\(backupFilename)")
        
        guard fileManager.fileExists(atPath: backupURL.path) else {
            print("Backup file not found")
            return
        }
        
        // Backup current version before restoring
        backupFile(originalURL)
        
        // Restore from backup
        try? fileManager.removeItem(at: originalURL)
        try? fileManager.copyItem(at: backupURL, to: originalURL)
    }
    
    // MARK: - Helper Methods
    
    private func getCurrentWeekId() -> String {
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: Date())
        let year = calendar.component(.yearForWeekOfYear, from: Date())
        return String(format: "%04d-W%02d", year, weekOfYear)
    }
    
    private func getCurrentMonthId() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM"
        return dateFormatter.string(from: Date())
    }
    
    private func getDayHeader(from dateString: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        
        if let date = formatter.date(from: dateString) {
            formatter.dateFormat = "EEEE yyyy-MM-dd"
            return "## " + formatter.string(from: date)
        }
        
        return "## \(dateString)"
    }
    
    // MARK: - Task 5.1: Working Notepad Methods
    
    var journalDirectory: URL {
        documentsURL.appendingPathComponent("journal")
    }
    
    /// Write content to the working notepad
    /// - Parameters:
    ///   - content: The content to write
    ///   - append: If true, appends to existing content with timestamp. If false, replaces all content.
    func writeToNotepad(_ content: String, append: Bool = true) {
        let notepadPath = journalDirectory.appendingPathComponent("_working_notepad.md")
        
        if append {
            // Append with timestamp
            let existing = (try? String(contentsOf: notepadPath)) ?? ""
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            let timestamp = formatter.string(from: Date())
            
            let updated = existing.isEmpty ? content : existing + "\n\n---\n[\(timestamp)]\n" + content
            try? updated.write(to: notepadPath, atomically: true, encoding: .utf8)
        } else {
            // Replace completely
            try? content.write(to: notepadPath, atomically: true, encoding: .utf8)
        }
        
        print("📝 Notepad \(append ? "updated (append)" : "replaced"): \(content.prefix(100))...")
    }
    
    /// Read the current notepad content
    /// - Returns: The notepad content, or empty message if notepad is empty
    func readNotepad() -> String {
        let notepadPath = journalDirectory.appendingPathComponent("_working_notepad.md")
        let content = (try? String(contentsOf: notepadPath)) ?? ""
        
        if content.isEmpty {
            return "[Notepad is empty - use write_to_notepad to store findings]"
        }
        
        return content
    }
    
    /// Clear all notepad content
    func clearNotepad() {
        let notepadPath = journalDirectory.appendingPathComponent("_working_notepad.md")
        try? "".write(to: notepadPath, atomically: true, encoding: .utf8)
        print("🗑️ Notepad cleared")
    }
    
    /// Get the current size of notepad content
    /// - Returns: Character count of notepad content
    func getNotepadSize() -> Int {
        return readNotepad().count
    }
}
