import SwiftUI

struct PeopleView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var people: [Person] = []
    @State private var showSuperHousekeeping = false
    @State private var isLoading = false
    
    var filteredPeople: [Person] {
        if searchText.isEmpty {
            return people
        }
        return people.filter { person in
            person.name.localizedCaseInsensitiveContains(searchText) ||
            person.role?.localizedCaseInsensitiveContains(searchText) == true ||
            person.company?.localizedCaseInsensitiveContains(searchText) == true
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Super Housekeeping button
                Button(action: {
                    showSuperHousekeeping = true
                }) {
                    HStack {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 24))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Super Housekeeping")
                                .font(.headline)
                            Text("Extract people from journal")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding()
                    .background(Color.purple)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                .padding()
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    TextField("Search people...", text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                .padding(.horizontal)
                
                // People list
                if isLoading {
                    Spacer()
                    ProgressView("Loading people...")
                    Spacer()
                } else if filteredPeople.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No people tracked yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Run Super Housekeeping to extract people from your journal")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(filteredPeople) { person in
                            NavigationLink(destination: PersonDetailView(person: person)) {
                                PersonRowView(person: person)
                            }
                        }
                    }
                    .listStyle(PlainListStyle())
                }
            }
            .navigationTitle("People")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadPeople()
            }
            .sheet(isPresented: $showSuperHousekeeping) {
                SuperHousekeepingView()
                    .environmentObject(appState)
                    .onDisappear {
                        loadPeople()
                    }
            }
        }
    }
    
    private func loadPeople() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let peopleManager = PeopleManager(fileManager: appState.fileManager)
            let loadedPeople = peopleManager.loadAllPeople()
            
            DispatchQueue.main.async {
                self.people = loadedPeople
                self.isLoading = false
            }
        }
    }
}

struct PersonRowView: View {
    let person: Person
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(person.name)
                    .font(.headline)
                Spacer()
                if let lastContact = person.lastContact {
                    Text(timeAgo(from: lastContact))
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            if let role = person.role {
                Text(role)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if let summary = person.summary {
                Text(summary)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            
            HStack(spacing: 16) {
                Label("\(person.interactions.count)", systemImage: "bubble.left.and.bubble.right")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                if !person.actionItems.isEmpty {
                    Label("\(person.actionItems.count)", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                
                if !person.keyTopics.isEmpty {
                    Label("\(person.keyTopics.count)", systemImage: "tag")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func timeAgo(from date: Date) -> String {
        let components = Calendar.current.dateComponents([.day, .hour], from: date, to: Date())
        
        if let days = components.day, days > 0 {
            return "\(days)d ago"
        } else if let hours = components.hour, hours > 0 {
            return "\(hours)h ago"
        } else {
            return "Just now"
        }
    }
}

struct PersonDetailView: View {
    let person: Person
    @State private var markdown: String = ""
    @State private var showingEditSheet = false
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text(person.name)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    // Aliases
                    if !person.aliases.isEmpty {
                        Text("AKA: \(person.aliases.joined(separator: ", "))")
                            .font(.subheadline)
                            .foregroundColor(.purple)
                            .italic()
                    }
                    
                    if let role = person.role {
                        Text(role)
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    
                    if let company = person.company {
                        Label(company, systemImage: "building.2")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                    }
                    
                    if let lastContact = person.lastContact {
                        Label("Last contact: \(formatDate(lastContact))", systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                
                // Summary
                if let summary = person.summary {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Summary", systemImage: "doc.text")
                            .font(.headline)
                        Text(summary)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Key Topics
                if !person.keyTopics.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Key Topics", systemImage: "tag.fill")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(person.keyTopics, id: \.self) { topic in
                                    Text(topic)
                                        .font(.caption)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.orange.opacity(0.2))
                                        .foregroundColor(.orange)
                                        .cornerRadius(16)
                                }
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                }
                
                // Action Items
                if !person.actionItems.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Action Items", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                        ForEach(person.actionItems, id: \.self) { item in
                            HStack(alignment: .top) {
                                Image(systemName: "circle")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Text(item)
                                    .font(.subheadline)
                            }
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(12)
                }
                
                // Recent Interactions
                if !person.interactions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Recent Interactions (\(person.interactions.count))", systemImage: "bubble.left.and.bubble.right.fill")
                            .font(.headline)
                        
                        ForEach(person.interactions.sorted { $0.date > $1.date }.prefix(20)) { interaction in
                            InteractionRowView(interaction: interaction)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.gray.opacity(0.05))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            PersonEditSheet(person: person)
                .environmentObject(appState)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

struct InteractionRowView: View {
    let interaction: PersonInteraction
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon based on type
            Image(systemName: iconForType(interaction.type))
                .foregroundColor(colorForType(interaction.type))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(interaction.type.rawValue)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(colorForType(interaction.type))
                    
                    Spacer()
                    
                    Text(dateString(from: interaction.date))
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    Text(interaction.time)
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                
                Text(interaction.content)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func iconForType(_ type: PersonInteraction.InteractionType) -> String {
        switch type {
        case .meeting: return "person.2.fill"
        case .call: return "phone.fill"
        case .message: return "message.fill"
        case .email: return "envelope.fill"
        case .note: return "note.text"
        }
    }
    
    private func colorForType(_ type: PersonInteraction.InteractionType) -> Color {
        switch type {
        case .meeting: return .blue
        case .call: return .green
        case .message: return .purple
        case .email: return .orange
        case .note: return .gray
        }
    }
    
    private func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Person Edit Sheet

struct PersonEditSheet: View {
    let person: Person
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var newAlias = ""
    @State private var showMergeSheet = false
    @State private var selectedPersonToMerge: Person?
    @State private var showingDeleteConfirmation = false
    @State private var showingDeletePersonConfirmation = false
    @State private var aliasToDelete: String?
    
    var body: some View {
        NavigationView {
            Form {
                // Aliases Section
                Section {
                    ForEach(person.aliases, id: \.self) { alias in
                        HStack {
                            Text(alias)
                            Spacer()
                            Button(action: {
                                aliasToDelete = alias
                                showingDeleteConfirmation = true
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    
                    // Add new alias
                    HStack {
                        TextField("Add alias (e.g., 'Jon', 'Jonathan')", text: $newAlias)
                        Button("Add") {
                            if !newAlias.isEmpty {
                                appState.peopleManager.addAlias(to: person.name, alias: newAlias)
                                newAlias = ""
                                dismiss()
                            }
                        }
                        .disabled(newAlias.isEmpty)
                    }
                } header: {
                    Text("Aliases / AKA")
                } footer: {
                    Text("Add other spellings or nicknames for \(person.name)")
                }
                
                // Merge Section
                Section {
                    Button(action: {
                        showMergeSheet = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.triangle.merge")
                            Text("Merge with Another Person")
                        }
                    }
                } header: {
                    Text("Merge People")
                } footer: {
                    Text("Combine two duplicate people into one. All interactions and data will be merged.")
                }
                
                // Delete Section
                Section {
                    Button(role: .destructive, action: {
                        showingDeletePersonConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Person")
                        }
                    }
                } header: {
                    Text("Danger Zone")
                } footer: {
                    Text("Permanently delete \(person.name) and all their data. This cannot be undone.")
                }
            }
            .navigationTitle("Edit \(person.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Delete Alias", isPresented: $showingDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let alias = aliasToDelete {
                        appState.peopleManager.removeAlias(from: person.name, alias: alias)
                        dismiss()
                    }
                }
            } message: {
                if let alias = aliasToDelete {
                    Text("Remove '\(alias)' as an alias for \(person.name)?")
                }
            }
            .alert("Delete Person", isPresented: $showingDeletePersonConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    appState.peopleManager.deletePerson(person)
                    dismiss()
                }
            } message: {
                Text("Are you sure you want to delete \(person.name)?\n\nThis will permanently delete:\n• \(person.interactions.count) interactions\n• Summary and all data\n\nThis cannot be undone.")
            }
            .sheet(isPresented: $showMergeSheet) {
                MergePersonSheet(primaryPerson: person)
                    .environmentObject(appState)
            }
        }
    }
}

// MARK: - Merge Person Sheet

struct MergePersonSheet: View {
    let primaryPerson: Person
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @State private var selectedPerson: Person?
    @State private var showingConfirmation = false
    @State private var allPeople: [Person] = []
    
    var otherPeople: [Person] {
        allPeople.filter { $0.id != primaryPerson.id }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    ForEach(otherPeople) { person in
                        Button(action: {
                            selectedPerson = person
                            showingConfirmation = true
                        }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(person.name)
                                    .font(.headline)
                                if !person.aliases.isEmpty {
                                    Text("AKA: \(person.aliases.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Text("\(person.interactions.count) interactions")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Select person to merge into \(primaryPerson.name)")
                } footer: {
                    Text("This will combine all interactions, aliases, and data from the selected person into \(primaryPerson.name). The selected person will be deleted.")
                }
            }
            .navigationTitle("Merge People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .alert("Confirm Merge", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Merge", role: .destructive) {
                    if let secondary = selectedPerson {
                        _ = appState.peopleManager.mergePeople(
                            primaryName: primaryPerson.name,
                            secondaryName: secondary.name
                        )
                        dismiss()
                    }
                }
            } message: {
                if let secondary = selectedPerson {
                    Text("Merge '\(secondary.name)' into '\(primaryPerson.name)'?\n\nThis will:\n• Combine \(secondary.interactions.count) interactions\n• Add '\(secondary.name)' as an alias\n• Delete '\(secondary.name)' as a separate person\n\nThis cannot be undone.")
                }
            }
            .onAppear {
                allPeople = appState.peopleManager.loadAllPeople()
            }
        }
    }
}
