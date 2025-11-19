import Foundation

class PeopleManager {
    private let fileManager: FileStorageManager
    private let peopleDirectory: URL
    private let indexFile: URL
    
    init(fileManager: FileStorageManager) {
        self.fileManager = fileManager
        self.peopleDirectory = fileManager.documentsURL.appendingPathComponent("people")
        self.indexFile = peopleDirectory.appendingPathComponent("_index.json")
        
        // Create people directory if it doesn't exist
        try? Foundation.FileManager.default.createDirectory(at: peopleDirectory, withIntermediateDirectories: true)
    }
    
    // MARK: - Load/Save Index
    
    func loadIndex() -> PeopleIndex {
        guard let data = try? Data(contentsOf: indexFile),
              let index = try? JSONDecoder().decode(PeopleIndex.self, from: data) else {
            return PeopleIndex()
        }
        return index
    }
    
    func saveIndex(_ index: PeopleIndex) {
        var updatedIndex = index
        updatedIndex.lastUpdated = Date()
        
        if let data = try? JSONEncoder().encode(updatedIndex) {
            try? data.write(to: indexFile)
        }
    }
    
    // MARK: - Load/Save Person
    
    func loadPerson(name: String) -> Person? {
        let index = loadIndex()
        guard let personId = index.people[name.lowercased()] else {
            return nil
        }
        
        // Find the person file by UUID (not by name, since aliases might not match filename)
        guard let fileURL = Foundation.FileManager.default.enumerator(at: peopleDirectory, includingPropertiesForKeys: nil)?.compactMap({ $0 as? URL }).first(where: { url in
            guard url.pathExtension == "json", url.lastPathComponent != "_index.json" else { return false }
            guard let data = try? Data(contentsOf: url),
                  let person = try? JSONDecoder().decode(Person.self, from: data) else {
                return false
            }
            return person.id == personId
        }) else {
            return nil
        }
        
        guard let data = try? Data(contentsOf: fileURL),
              let person = try? JSONDecoder().decode(Person.self, from: data) else {
            return nil
        }
        
        return person
    }
    
    func savePerson(_ person: Person) {
        var updatedPerson = person
        updatedPerson.updatedAt = Date()
        
        // Save person file
        let personFile = peopleDirectory.appendingPathComponent("\(person.fileName).json")
        if let data = try? JSONEncoder().encode(updatedPerson) {
            try? data.write(to: personFile)
        }
        
        // Update index - map primary name AND all aliases to person ID
        var index = loadIndex()
        index.people[person.name.lowercased()] = person.id
        for alias in person.aliases {
            index.people[alias.lowercased()] = person.id
        }
        saveIndex(index)
        
        print("💾 Saved person: \(person.name)")
    }
    
    func loadAllPeople() -> [Person] {
        let index = loadIndex()
        var peopleById: [UUID: Person] = [:]  // Deduplicate by UUID
        
        for (name, personId) in index.people {
            // Skip if we already loaded this person
            if peopleById[personId] != nil {
                continue
            }
            
            if let person = loadPerson(name: name) {
                peopleById[person.id] = person
            }
        }
        
        return Array(peopleById.values).sorted { $0.name < $1.name }
    }
    
    // MARK: - Person Operations
    
    func getOrCreatePerson(name: String) -> Person {
        if let existing = loadPerson(name: name) {
            return existing
        }
        
        let newPerson = Person(name: name)
        savePerson(newPerson)
        return newPerson
    }
    
    func addInteraction(to personName: String, interaction: PersonInteraction) {
        var person = getOrCreatePerson(name: personName)
        
        // Check for duplicates
        let isDuplicate = person.interactions.contains { existing in
            existing.date == interaction.date &&
            existing.time == interaction.time &&
            existing.content == interaction.content
        }
        
        if !isDuplicate {
            person.interactions.append(interaction)
            person.lastContact = interaction.date
            savePerson(person)
            print("✅ Added interaction for \(personName): \(interaction.content.prefix(50))...")
        } else {
            print("⏭️  Skipping duplicate interaction for \(personName)")
        }
    }
    
    func updatePersonSummary(name: String, summary: String) {
        var person = getOrCreatePerson(name: name)
        person.summary = summary
        savePerson(person)
    }
    
    func addActionItem(to personName: String, actionItem: String) {
        var person = getOrCreatePerson(name: personName)
        
        if !person.actionItems.contains(actionItem) {
            person.actionItems.append(actionItem)
            savePerson(person)
        }
    }
    
    func addKeyTopic(to personName: String, topic: String) {
        var person = getOrCreatePerson(name: personName)
        
        if !person.keyTopics.contains(topic) {
            person.keyTopics.append(topic)
            savePerson(person)
        }
    }
    
    // MARK: - Search
    
    func searchPeople(query: String) -> [Person] {
        let allPeople = loadAllPeople()
        let lowercasedQuery = query.lowercased()
        
        return allPeople.filter { person in
            person.name.lowercased().contains(lowercasedQuery) ||
            person.role?.lowercased().contains(lowercasedQuery) == true ||
            person.company?.lowercased().contains(lowercasedQuery) == true
        }
    }
    
    // MARK: - Merge & Aliases
    
    /// Add an alias (AKA) to a person
    func addAlias(to personName: String, alias: String) {
        var person = getOrCreatePerson(name: personName)
        
        let cleanAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanAlias.isEmpty && !person.aliases.contains(cleanAlias) && cleanAlias.lowercased() != person.name.lowercased() {
            person.aliases.append(cleanAlias)
            savePerson(person)
            
            // Update index to map alias to this person
            var index = loadIndex()
            index.people[cleanAlias.lowercased()] = person.id
            saveIndex(index)
            
            print("✅ Added alias '\(cleanAlias)' to \(personName)")
        }
    }
    
    /// Remove an alias from a person
    func removeAlias(from personName: String, alias: String) {
        var person = getOrCreatePerson(name: personName)
        
        if let index = person.aliases.firstIndex(of: alias) {
            person.aliases.remove(at: index)
            savePerson(person)
            
            // Remove from index
            var peopleIndex = loadIndex()
            peopleIndex.people.removeValue(forKey: alias.lowercased())
            saveIndex(peopleIndex)
            
            print("✅ Removed alias '\(alias)' from \(personName)")
        }
    }
    
    /// Merge two people into one, combining all their data
    func mergePeople(primaryName: String, secondaryName: String) -> Person? {
        guard var primaryPerson = loadPerson(name: primaryName),
              let secondaryPerson = loadPerson(name: secondaryName) else {
            print("❌ Failed to merge: couldn't load both people")
            return nil
        }
        
        print("🔀 Merging \(secondaryName) into \(primaryName)...")
        
        // Add secondary name as alias
        if !primaryPerson.aliases.contains(secondaryName) {
            primaryPerson.aliases.append(secondaryName)
        }
        
        // Merge aliases
        for alias in secondaryPerson.aliases {
            if !primaryPerson.aliases.contains(alias) {
                primaryPerson.aliases.append(alias)
            }
        }
        
        // Merge interactions (avoiding duplicates)
        for interaction in secondaryPerson.interactions {
            let isDuplicate = primaryPerson.interactions.contains { existing in
                existing.date == interaction.date &&
                existing.time == interaction.time &&
                existing.content == interaction.content
            }
            
            if !isDuplicate {
                primaryPerson.interactions.append(interaction)
            }
        }
        
        // Sort interactions by date
        primaryPerson.interactions.sort { $0.date > $1.date }
        
        // Merge action items
        for item in secondaryPerson.actionItems {
            if !primaryPerson.actionItems.contains(item) {
                primaryPerson.actionItems.append(item)
            }
        }
        
        // Merge key topics
        for topic in secondaryPerson.keyTopics {
            if !primaryPerson.keyTopics.contains(topic) {
                primaryPerson.keyTopics.append(topic)
            }
        }
        
        // Use most recent last contact
        if let secondaryContact = secondaryPerson.lastContact {
            if let primaryContact = primaryPerson.lastContact {
                primaryPerson.lastContact = max(primaryContact, secondaryContact)
            } else {
                primaryPerson.lastContact = secondaryContact
            }
        }
        
        // Keep the more detailed information
        if primaryPerson.role == nil && secondaryPerson.role != nil {
            primaryPerson.role = secondaryPerson.role
        }
        if primaryPerson.company == nil && secondaryPerson.company != nil {
            primaryPerson.company = secondaryPerson.company
        }
        
        // Combine summaries if both exist
        if let primarySummary = primaryPerson.summary, let secondarySummary = secondaryPerson.summary {
            primaryPerson.summary = "\(primarySummary)\n\n[Merged from \(secondaryName)]: \(secondarySummary)"
        } else if primaryPerson.summary == nil {
            primaryPerson.summary = secondaryPerson.summary
        }
        
        // Save merged person
        savePerson(primaryPerson)
        
        // Update index - map all secondary names to primary person
        var index = loadIndex()
        index.people[secondaryName.lowercased()] = primaryPerson.id
        for alias in secondaryPerson.aliases {
            index.people[alias.lowercased()] = primaryPerson.id
        }
        saveIndex(index)
        
        // Delete secondary person file
        let secondaryFileName = secondaryName.lowercased()
            .replacingOccurrences(of: " ", with: "-")
            .replacingOccurrences(of: "[^a-z0-9-]", with: "", options: .regularExpression)
        let secondaryFile = peopleDirectory.appendingPathComponent("\(secondaryFileName).json")
        try? Foundation.FileManager.default.removeItem(at: secondaryFile)
        
        print("✅ Merged \(secondaryName) into \(primaryName)")
        print("   - Combined \(secondaryPerson.interactions.count) interactions")
        print("   - Added \(secondaryName) as alias")
        
        return primaryPerson
    }
    
    // MARK: - Delete Person
    
    /// Delete a person and remove all their index entries
    func deletePerson(_ person: Person) {
        print("🗑️ Deleting \(person.name)...")
        
        // Delete the person file
        let personFile = peopleDirectory.appendingPathComponent("\(person.fileName).json")
        try? Foundation.FileManager.default.removeItem(at: personFile)
        
        // Remove from index - remove ALL entries pointing to this UUID
        var index = loadIndex()
        index.people = index.people.filter { $0.value != person.id }
        saveIndex(index)
        
        print("✅ Deleted \(person.name) and removed from index")
    }
    
    // MARK: - Cleanup Index
    
    /// Clean up the index to remove orphaned entries and ensure consistency
    func cleanupIndex() {
        print("🧹 Cleaning up index...")
        var index = loadIndex()
        var validPeople: [UUID: Person] = [:]
        
        // Scan all person files to build valid UUID set
        if let enumerator = Foundation.FileManager.default.enumerator(at: peopleDirectory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "json",
                      fileURL.lastPathComponent != "_index.json",
                      let data = try? Data(contentsOf: fileURL),
                      let person = try? JSONDecoder().decode(Person.self, from: data) else {
                    continue
                }
                validPeople[person.id] = person
            }
        }
        
        print("📂 Found \(validPeople.count) valid person files")
        
        // Rebuild index from scratch based on actual files
        var newIndex = PeopleIndex()
        for person in validPeople.values {
            // Map primary name
            newIndex.people[person.name.lowercased()] = person.id
            
            // Map all aliases
            for alias in person.aliases {
                newIndex.people[alias.lowercased()] = person.id
            }
        }
        
        saveIndex(newIndex)
        print("✅ Index cleaned: \(newIndex.people.count) name mappings for \(validPeople.count) people")
    }
    
    // MARK: - Export to Markdown
    
    func exportPersonToMarkdown(_ person: Person) -> String {
        var markdown = "# \(person.name)\n\n"
        
        // Aliases
        if !person.aliases.isEmpty {
            markdown += "_Also known as: \(person.aliases.joined(separator: ", "))_\n\n"
        }
        
        // Summary section
        markdown += "## Summary\n"
        if let summary = person.summary {
            markdown += "\(summary)\n\n"
        }
        if let role = person.role {
            markdown += "- **Role**: \(role)\n"
        }
        if let company = person.company {
            markdown += "- **Company**: \(company)\n"
        }
        if let lastContact = person.lastContact {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            markdown += "- **Last Contact**: \(formatter.string(from: lastContact))\n"
        }
        markdown += "\n"
        
        // Key Topics
        if !person.keyTopics.isEmpty {
            markdown += "## Key Topics\n"
            for topic in person.keyTopics {
                markdown += "- \(topic)\n"
            }
            markdown += "\n"
        }
        
        // Action Items
        if !person.actionItems.isEmpty {
            markdown += "## Action Items\n"
            for item in person.actionItems {
                markdown += "- [ ] \(item)\n"
            }
            markdown += "\n"
        }
        
        // Recent Interactions
        if !person.interactions.isEmpty {
            markdown += "## Recent Interactions\n"
            let sortedInteractions = person.interactions.sorted { $0.date > $1.date }
            for interaction in sortedInteractions.prefix(20) {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                markdown += "- **[\(formatter.string(from: interaction.date)) \(interaction.time)]** \(interaction.type.rawValue): \(interaction.content)\n"
            }
            markdown += "\n"
        }
        
        return markdown
    }
}
