import SwiftUI

struct JournalView: View {
    @State private var selectedPeriod: JournalPeriod = .weeks
    @State private var journalFiles: [JournalFile] = []
    
    enum JournalPeriod: String, CaseIterable {
        case weeks = "Weeks"
        case months = "Months"
        case years = "Years"
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Picker("Period", selection: $selectedPeriod) {
                    ForEach(JournalPeriod.allCases, id: \.self) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
                
                List(journalFiles) { file in
                    NavigationLink(destination: JournalDetailView(file: file)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(file.name)
                                .font(.headline)
                            
                            Text(file.type)
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            if let date = file.modifiedDate {
                                Text("Modified: \(formatDate(date))")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Journal")
            .onAppear {
                loadJournalFiles()
            }
            .onChange(of: selectedPeriod) { _ in
                loadJournalFiles()
            }
        }
    }
    
    private func loadJournalFiles() {
        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        let subdirectory: String
        switch selectedPeriod {
        case .weeks:
            subdirectory = "journal/weeks"
        case .months:
            subdirectory = "journal/months"
        case .years:
            subdirectory = "journal/years"
        }
        
        let journalDir = documentsURL.appendingPathComponent(subdirectory)
        
        guard let files = try? fileManager.contentsOfDirectory(at: journalDir, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            journalFiles = []
            return
        }
        
        journalFiles = files
            .filter { $0.pathExtension == "md" }
            .compactMap { url -> JournalFile? in
                let name = url.deletingPathExtension().lastPathComponent
                let type = name.contains("detailed") ? "Detailed" : "Summary"
                let modifiedDate = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                
                return JournalFile(url: url, name: name, type: type, modifiedDate: modifiedDate)
            }
            .sorted { ($0.modifiedDate ?? Date.distantPast) > ($1.modifiedDate ?? Date.distantPast) }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct JournalFile: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let type: String
    let modifiedDate: Date?
}

struct JournalDetailView: View {
    let file: JournalFile
    @State private var content: String = ""
    @State private var editedContent: String = ""
    @State private var isEditing: Bool = false
    @State private var showingSaveConfirmation: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            if isEditing {
                TextEditor(text: $editedContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Use disabled TextEditor for read-only - it works when editing
                TextEditor(text: .constant(content))
                    .font(.system(.body, design: .monospaced))
                    .disabled(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .navigationTitle(file.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if isEditing {
                    Button("Save") {
                        saveContent()
                    }
                } else {
                    Button("Edit") {
                        editedContent = content  // Copy content to editedContent
                        isEditing = true
                    }
                }
            }
            if isEditing {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isEditing = false
                        loadContent() // Reload original content
                    }
                }
            }
        }
        .alert("Saved", isPresented: $showingSaveConfirmation) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Journal entry saved successfully")
        }
        .onAppear {
            loadContent()
        }
    }
    
    private func loadContent() {
        if let fileContent = try? String(contentsOf: file.url) {
            content = fileContent
        } else {
            content = "Failed to load journal content"
        }
    }
    
    private func saveContent() {
        do {
            try editedContent.write(to: file.url, atomically: true, encoding: .utf8)
            content = editedContent  // Update content with saved changes
            isEditing = false
            showingSaveConfirmation = true
        } catch {
            print("Failed to save: \(error)")
        }
    }
}
