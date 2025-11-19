import SwiftUI

struct FilesView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingDocumentPicker = false
    
    var documentsURL: URL {
        appState.fileManager.documentsURL
    }
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Location")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Files are saved to:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("On My iPhone › TenX")
                            .font(.headline)
                        
                        Text(documentsURL.path)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                        
                        Button(action: {
                            showingDocumentPicker = true
                        }) {
                            Label("Open in Files App", systemImage: "folder")
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section(header: Text("Journal Files")) {
                    NavigationLink(destination: FolderBrowserView(folderPath: "journal/weeks")) {
                        FileLink(
                            title: "Current Week Journal",
                            path: "journal/weeks/",
                            icon: "book.fill",
                            color: .blue
                        )
                    }
                    NavigationLink(destination: FolderBrowserView(folderPath: "journal/weeks")) {
                        FileLink(
                            title: "Weekly Summaries",
                            path: "journal/weeks/",
                            icon: "calendar",
                            color: .green
                        )
                    }
                    NavigationLink(destination: FolderBrowserView(folderPath: "journal/months")) {
                        FileLink(
                            title: "Monthly Summaries",
                            path: "journal/months/",
                            icon: "calendar.badge.clock",
                            color: .orange
                        )
                    }
                    NavigationLink(destination: FolderBrowserView(folderPath: "journal/years")) {
                        FileLink(
                            title: "Yearly Summaries",
                            path: "journal/years/",
                            icon: "calendar.circle",
                            color: .purple
                        )
                    }
                }
                
                Section(header: Text("Other Files")) {
                    NavigationLink(destination: FolderBrowserView(folderPath: "tasks")) {
                        FileLink(
                            title: "Tasks",
                            path: "tasks/",
                            icon: "checkmark.circle.fill",
                            color: .blue
                        )
                    }
                    NavigationLink(destination: FolderBrowserView(folderPath: "utterances")) {
                        FileLink(
                            title: "Utterances (Transcripts)",
                            path: "utterances/",
                            icon: "text.bubble.fill",
                            color: .cyan
                        )
                    }
                    NavigationLink(destination: FolderBrowserView(folderPath: "audio_raw")) {
                        FileLink(
                            title: "Audio Recordings",
                            path: "audio_raw/",
                            icon: "waveform",
                            color: .red
                        )
                    }
                    Button(action: {
                        // Open chat sessions file
                        if let url = URL(string: "shareddocuments://\(documentsURL.path)/chat_sessions.json") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        FileLink(
                            title: "Chat Sessions",
                            path: "chat_sessions.json",
                            icon: "message.fill",
                            color: .green
                        )
                    }
                }
                
                Section(header: Text("How to Edit")) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Text("1️⃣")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Open Files App")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Tap the button above or open Files app")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Text("2️⃣")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Navigate to TenX folder")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("On My iPhone › TenX › journal/weeks/")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        HStack(alignment: .top, spacing: 12) {
                            Text("3️⃣")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Tap any .md file to edit")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text("Files ending in .md are markdown text files")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Files")
            .sheet(isPresented: $showingDocumentPicker) {
                DocumentPicker(url: documentsURL)
            }
        }
    }
}

struct FileLink: View {
    let title: String
    let path: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                Text(path)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct FolderBrowserView: View {
    let folderPath: String
    @State private var files: [FileItem] = []
    
    var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    
    var body: some View {
        List {
            ForEach(files) { file in
                NavigationLink(destination: FileDetailView(file: file)) {
                    HStack(spacing: 12) {
                        Image(systemName: file.isDirectory ? "folder.fill" : "doc.text.fill")
                            .foregroundColor(file.isDirectory ? .blue : .gray)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .font(.subheadline)
                            
                            if let date = file.modifiedDate {
                                Text(formatDate(date))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(folderPath.components(separatedBy: "/").last ?? "Files")
        .onAppear {
            loadFiles()
        }
    }
    
    private func loadFiles() {
        let folderURL = documentsURL.appendingPathComponent(folderPath)
        
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey]
        ) else {
            files = []
            return
        }
        
        files = contents.compactMap { url in
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let modifiedDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            
            return FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: isDirectory,
                modifiedDate: modifiedDate
            )
        }.sorted { $0.name < $1.name }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct FileItem: Identifiable {
    let id = UUID()
    let url: URL
    let name: String
    let isDirectory: Bool
    let modifiedDate: Date?
}

struct FileDetailView: View {
    let file: FileItem
    @State private var content: String = ""
    @State private var isEditing: Bool = false
    
    var body: some View {
        VStack {
            if isEditing {
                TextEditor(text: $content)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.primary)
                    .padding()
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.primary)
                        .padding()
                        .textSelection(.enabled)
                }
            }
        }
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
                        isEditing = true
                    }
                }
            }
            if isEditing {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isEditing = false
                        loadContent()
                    }
                }
            }
        }
        .onAppear {
            loadContent()
        }
    }
    
    private func loadContent() {
        if let fileContent = try? String(contentsOf: file.url) {
            content = fileContent
        } else {
            content = "Failed to load file content"
        }
    }
    
    private func saveContent() {
        do {
            try content.write(to: file.url, atomically: true, encoding: .utf8)
            isEditing = false
        } catch {
            print("Failed to save: \(error)")
        }
    }
}

struct DocumentPicker: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.directoryURL = url
        picker.shouldShowFileExtensions = true
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
}
