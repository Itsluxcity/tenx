import Foundation

class SuperHousekeepingService {
    private let fileManager: FileStorageManager
    private let peopleManager: PeopleManager
    private let claudeService: ClaudeService
    
    var onProgress: ((String) -> Void)?
    
    init(
        fileManager: FileStorageManager,
        peopleManager: PeopleManager,
        claudeService: ClaudeService
    ) {
        self.fileManager = fileManager
        self.peopleManager = peopleManager
        self.claudeService = claudeService
    }
    
    func runSuperHousekeeping() async -> SuperHousekeepingResult {
        var result = SuperHousekeepingResult()
        
        print("🧹✨ ========== SUPER HOUSEKEEPING START ==========")
        print("🧹✨ Timestamp: \(Date())")
        onProgress?("🧹 Starting Super Housekeeping...")
        
        // Step 1: Extract people from journal
        print("🧹✨ STEP 1: Extracting people from journal...")
        onProgress?("📖 Step 1: Analyzing journal...")
        let extractionResult = await extractPeopleFromJournal()
        result.peopleFound = extractionResult.peopleFound
        result.interactionsExtracted = extractionResult.interactionsExtracted
        print("✅ STEP 1 COMPLETE: Found \(extractionResult.peopleFound) people, \(extractionResult.interactionsExtracted) interactions")
        onProgress?("✅ Found \(extractionResult.peopleFound) people, \(extractionResult.interactionsExtracted) interactions")
        
        // Step 2: Update person files
        print("🧹✨ STEP 2: Updating person files...")
        onProgress?("👤 Step 2: Updating person files...")
        let updateResult = await updatePersonFiles(extractionResult.peopleData)
        result.peopleUpdated = updateResult.peopleUpdated
        result.duplicatesRemoved = updateResult.duplicatesRemoved
        print("✅ STEP 2 COMPLETE: Updated \(updateResult.peopleUpdated) people, removed \(updateResult.duplicatesRemoved) duplicates")
        onProgress?("✅ Updated \(updateResult.peopleUpdated) people")
        
        // Step 3: Generate summaries
        print("🧹✨ STEP 3: Generating person summaries...")
        onProgress?("📝 Step 3: Generating AI summaries...")
        let summariesGenerated = await generatePersonSummaries()
        result.summariesGenerated = summariesGenerated
        print("✅ STEP 3 COMPLETE: Generated \(summariesGenerated) summaries")
        onProgress?("✅ Generated \(summariesGenerated) summaries")
        
        // Step 4: Cleanup index
        print("🧹✨ STEP 4: Cleaning up index...")
        onProgress?("🔧 Step 4: Cleaning up index...")
        peopleManager.cleanupIndex()
        print("✅ STEP 4 COMPLETE: Index cleaned")
        onProgress?("✅ Index cleaned")
        
        print("✅ ========== SUPER HOUSEKEEPING COMPLETE ==========")
        print("✅ Summary: Found \(result.peopleFound) people, \(result.interactionsExtracted) interactions, updated \(result.peopleUpdated) files")
        onProgress?("🎉 Complete! \(result.peopleFound) people tracked")
        
        return result
    }
    
    private func extractPeopleFromJournal() async -> (peopleFound: Int, interactionsExtracted: Int, peopleData: [String: [PersonInteraction]]) {
        let journal = fileManager.loadCurrentWeekDetailedJournal()
        
        print("📖 Journal length: \(journal.count) characters")
        
        // Process journal in chunks to avoid rate limits
        let chunkSize = 10000
        var allPeopleData: [String: [PersonInteraction]] = [:]
        var offset = 0
        
        while offset < journal.count {
            let startIndex = journal.index(journal.startIndex, offsetBy: offset)
            let endIndex = journal.index(startIndex, offsetBy: min(chunkSize, journal.count - offset))
            let chunk = String(journal[startIndex..<endIndex])
            
            print("📖 Processing chunk \(offset)-\(offset + chunk.count) of \(journal.count)")
            onProgress?("📖 Processing chunk \(offset/1000)k-\((offset+chunk.count)/1000)k...")
            
            // Extract people from this chunk
            let prompt = """
            Analyze this journal chunk and extract ALL people mentioned.
            
            For each person found, respond with ONLY their name on a new line, like:
            Marco
            Jessica
            Nick
            Sarah
            
            DO NOT include any other text. Just list the names, one per line.
            
            Journal chunk:
            \(chunk)
            """
            
            do {
                let context = ClaudeContext(
                    currentWeekJournal: "",
                    weeklySummaries: [],
                    monthlySummary: nil,
                    tasks: [],
                    upcomingEvents: [],
                    recentEvents: [],
                    reminders: [],
                    currentDate: Date()
                )
                
                let response = try await claudeService.sendMessage(
                    text: prompt,
                    context: context,
                    conversationHistory: [],
                    tools: []
                )
                
                // Parse names from response
                let names = response.content
                    .components(separatedBy: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.contains(":") && $0.count < 50 }
                
                print("📖 Found \(names.count) people in this chunk: \(names.joined(separator: ", "))")
                if names.count > 0 {
                    onProgress?("👥 Found: \(names.prefix(3).joined(separator: ", "))...")
                }
                
                // For each person, extract their interactions from this chunk
                for name in names {
                    if allPeopleData[name] == nil {
                        allPeopleData[name] = []
                    }
                    
                    // Extract interactions for this person from the chunk
                    let interactions = extractInteractionsForPerson(name: name, fromText: chunk)
                    allPeopleData[name]?.append(contentsOf: interactions)
                }
                
            } catch {
                print("❌ Failed to extract from chunk: \(error)")
            }
            
            offset += chunkSize
        }
        
        let totalInteractions = allPeopleData.values.reduce(0) { $0 + $1.count }
        print("📊 Total: \(allPeopleData.count) people, \(totalInteractions) interactions")
        
        return (allPeopleData.count, totalInteractions, allPeopleData)
    }
    
    private func extractInteractionsForPerson(name: String, fromText text: String) -> [PersonInteraction] {
        var interactions: [PersonInteraction] = []
        
        // Split into lines
        let lines = text.components(separatedBy: "\n")
        
        for line in lines {
            let lowercased = line.lowercased()
            
            // Check if this line mentions the person (must be word boundary to avoid false matches)
            let namePattern = "\\b" + NSRegularExpression.escapedPattern(for: name.lowercased()) + "\\b"
            if lowercased.range(of: namePattern, options: .regularExpression) != nil {
                // Try to extract time pattern like [14:30] or (2:30 PM)
                var time = ""
                var content = line
                
                // Pattern: [14:30] or [2:30 PM]
                if let range = line.range(of: #"\[\d{1,2}:\d{2}[^\]]*\]"#, options: .regularExpression) {
                    time = String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                    content = line.replacingOccurrences(of: String(line[range]), with: "").trimmingCharacters(in: .whitespaces)
                }
                
                // Determine type
                var type: PersonInteraction.InteractionType = .note
                if lowercased.contains("meeting") || lowercased.contains("met with") {
                    type = .meeting
                } else if lowercased.contains("call") || lowercased.contains("called") {
                    type = .call
                } else if lowercased.contains("text") || lowercased.contains("message") {
                    type = .message
                } else if lowercased.contains("email") {
                    type = .email
                }
                
                // Clean up content
                content = content.trimmingCharacters(in: CharacterSet(charactersIn: "-*• "))
                
                if !content.isEmpty && content.count > 10 {
                    let interaction = PersonInteraction(
                        date: Date(), // Use today's date
                        time: time.isEmpty ? "00:00" : time,
                        content: content,
                        type: type
                    )
                    interactions.append(interaction)
                }
            }
        }
        
        return interactions
    }
    
    private func parseClaudeExtraction(_ text: String) -> [String: [PersonInteraction]] {
        var peopleData: [String: [PersonInteraction]] = [:]
        
        let lines = text.components(separatedBy: "\n")
        var currentPerson: String?
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Check for person header
            if trimmed.hasPrefix("PERSON:") {
                currentPerson = trimmed.replacingOccurrences(of: "PERSON:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let person = currentPerson {
                    peopleData[person] = []
                }
            }
            // Check for interaction line
            else if trimmed.hasPrefix("-"), let person = currentPerson {
                // Parse: - [Date] [Time] [Type]: [Content]
                let content = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
                
                // Try to extract date, time, type
                let components = content.components(separatedBy: "]")
                if components.count >= 3 {
                    let dateStr = components[0].replacingOccurrences(of: "[", with: "").trimmingCharacters(in: .whitespaces)
                    let timeStr = components[1].replacingOccurrences(of: "[", with: "").trimmingCharacters(in: .whitespaces)
                    let rest = components[2...].joined(separator: "]")
                    
                    let typeAndContent = rest.components(separatedBy: ":")
                    let typeStr = typeAndContent[0].replacingOccurrences(of: "[", with: "").trimmingCharacters(in: .whitespaces)
                    let contentStr = typeAndContent.dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
                    
                    let date = parseDateString(dateStr) ?? Date()
                    let type = parseInteractionType(typeStr)
                    
                    let interaction = PersonInteraction(
                        date: date,
                        time: timeStr,
                        content: contentStr,
                        type: type
                    )
                    
                    peopleData[person]?.append(interaction)
                }
            }
        }
        
        return peopleData
    }
    
    private func parseDateString(_ dateStr: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let date = formatter.date(from: dateStr) {
            return date
        }
        
        formatter.dateFormat = "MM/dd/yyyy"
        if let date = formatter.date(from: dateStr) {
            return date
        }
        
        formatter.dateFormat = "MMM dd, yyyy"
        if let date = formatter.date(from: dateStr) {
            return date
        }
        
        return nil
    }
    
    private func parseInteractionType(_ typeStr: String) -> PersonInteraction.InteractionType {
        let lowercased = typeStr.lowercased()
        if lowercased.contains("meeting") {
            return .meeting
        } else if lowercased.contains("call") {
            return .call
        } else if lowercased.contains("message") || lowercased.contains("text") {
            return .message
        } else if lowercased.contains("email") {
            return .email
        } else {
            return .note
        }
    }
    
    private func updatePersonFiles(_ peopleData: [String: [PersonInteraction]]) async -> (peopleUpdated: Int, duplicatesRemoved: Int) {
        var peopleUpdated = 0
        var duplicatesRemoved = 0
        
        for (personName, interactions) in peopleData {
            print("👤 Processing \(personName): \(interactions.count) interactions")
            
            var person = peopleManager.getOrCreatePerson(name: personName)
            let initialCount = person.interactions.count
            
            // Add interactions (with duplicate checking)
            for interaction in interactions {
                let isDuplicate = person.interactions.contains { existing in
                    existing.date == interaction.date &&
                    existing.time == interaction.time &&
                    existing.content == interaction.content
                }
                
                if !isDuplicate {
                    person.interactions.append(interaction)
                } else {
                    duplicatesRemoved += 1
                }
            }
            
            // Update last contact
            if let lastInteraction = person.interactions.max(by: { $0.date < $1.date }) {
                person.lastContact = lastInteraction.date
            }
            
            peopleManager.savePerson(person)
            peopleUpdated += 1
            
            let newInteractions = person.interactions.count - initialCount
            print("✅ Updated \(personName): +\(newInteractions) new interactions")
        }
        
        return (peopleUpdated, duplicatesRemoved)
    }
    
    private func generatePersonSummaries() async -> Int {
        let allPeople = peopleManager.loadAllPeople()
        var summariesGenerated = 0
        
        for person in allPeople {
            // Skip if no interactions
            if person.interactions.isEmpty {
                print("⏭️  Skipping \(person.name) - no interactions")
                continue
            }
            
            // Skip if already has good summary (not broken)
            if let summary = person.summary, !summary.isEmpty {
                // Check if summary is broken (contains tool call XML or thinking)
                let isBroken = summary.contains("<function_call>") || 
                               summary.contains("<tool_call>") ||
                               summary.contains("I need to") ||
                               summary.contains("Let me search")
                
                if !isBroken {
                    print("⏭️  Skipping \(person.name) - already has summary")
                    continue
                } else {
                    print("🔧 Regenerating broken summary for \(person.name)")
                }
            }
            
            print("📝 Generating summary for \(person.name)...")
            onProgress?("📝 Summarizing \(person.name)...")
            
            // Format interactions for Claude
            let interactionsList = person.interactions.prefix(10).map { interaction in
                "- [\(interaction.date.formatted())] \(interaction.time): \(interaction.content)"
            }.joined(separator: "\n")
            
            let prompt = """
            Based on these interactions, write a concise 2-3 sentence summary about \(person.name). Focus on who they are, your relationship, and key context. DO NOT use any tools or function calls - just provide the summary text directly.
            
            Recent interactions:
            \(interactionsList)
            
            Write the summary now (text only, no tools):
            """
            
            do {
                let context = ClaudeContext(
                    currentWeekJournal: "",
                    weeklySummaries: [],
                    monthlySummary: nil,
                    tasks: [],
                    upcomingEvents: [],
                    recentEvents: [],
                    reminders: [],
                    currentDate: Date()
                )
                
                let response = try await claudeService.sendMessage(
                    text: prompt,
                    context: context,
                    conversationHistory: [],
                    tools: []
                )
                
                // Clean up the response - remove any tool call XML or thinking
                var summary = response.content
                if summary.contains("<function_call>") || summary.contains("<tool_call>") {
                    summary = "Based on recent interactions: \(person.name) has been active in the journal."
                }
                
                peopleManager.updatePersonSummary(name: person.name, summary: summary)
                summariesGenerated += 1
                print("✅ Generated summary for \(person.name)")
                onProgress?("✅ \(person.name) complete (\(summariesGenerated) done)")
                
                // Add delay to avoid rate limits (wait 2 seconds between calls)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                
            } catch {
                print("❌ Failed to generate summary for \(person.name): \(error)")
                // On rate limit, wait longer before continuing
                if error.localizedDescription.contains("rate_limit") {
                    print("⏸️  Rate limit hit - waiting 5 seconds...")
                    try? await Task.sleep(nanoseconds: 5_000_000_000)
                }
            }
        }
        
        return summariesGenerated
    }
}

struct SuperHousekeepingResult: Codable {
    var peopleFound: Int = 0
    var interactionsExtracted: Int = 0
    var peopleUpdated: Int = 0
    var duplicatesRemoved: Int = 0
    var summariesGenerated: Int = 0
    var errors: [String] = []
    
    var summary: String {
        """
        Found \(peopleFound) people, extracted \(interactionsExtracted) interactions. \
        Updated \(peopleUpdated) person files, removed \(duplicatesRemoved) duplicates, generated \(summariesGenerated) summaries.
        """
    }
}
