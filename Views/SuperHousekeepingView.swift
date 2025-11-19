import SwiftUI

struct SuperHousekeepingView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var appState: AppState
    @State private var isRunning = false
    @State private var result: SuperHousekeepingResult?
    @State private var progressMessage = ""
    @State private var progressLog: [String] = []
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                if isRunning {
                    // Running state with live progress
                    VStack(spacing: 24) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text(progressMessage.isEmpty ? "Running Super Housekeeping..." : progressMessage)
                            .font(.title3)
                            .fontWeight(.semibold)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        // Progress log
                        if !progressLog.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Progress:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(progressLog.suffix(10), id: \.self) { log in
                                            Text(log)
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .frame(maxHeight: 200)
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    
                } else if let result = result {
                    // Results state
                    ScrollView {
                        VStack(spacing: 16) {
                            // Success header
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 60))
                                    .foregroundColor(.green)
                                
                                Text("Super Housekeeping Complete!")
                                    .font(.title2)
                                    .fontWeight(.bold)
                            }
                            .padding()
                            
                            // Results summary
                            VStack(spacing: 12) {
                                ResultRow(
                                    icon: "person.3.fill",
                                    label: "People Found",
                                    value: "\(result.peopleFound)",
                                    color: .blue
                                )
                                
                                ResultRow(
                                    icon: "bubble.left.and.bubble.right.fill",
                                    label: "Interactions Extracted",
                                    value: "\(result.interactionsExtracted)",
                                    color: .green
                                )
                                
                                ResultRow(
                                    icon: "arrow.triangle.2.circlepath",
                                    label: "People Updated",
                                    value: "\(result.peopleUpdated)",
                                    color: .orange
                                )
                                
                                ResultRow(
                                    icon: "trash.fill",
                                    label: "Duplicates Removed",
                                    value: "\(result.duplicatesRemoved)",
                                    color: .purple
                                )
                                
                                ResultRow(
                                    icon: "doc.text.fill",
                                    label: "Summaries Generated",
                                    value: "\(result.summariesGenerated)",
                                    color: .pink
                                )
                            }
                            .padding()
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(12)
                            
                            // Action buttons
                            VStack(spacing: 12) {
                                Button(action: {
                                    dismiss()
                                }) {
                                    HStack {
                                        Image(systemName: "person.3.fill")
                                        Text("View People")
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                }
                                
                                Button(action: {
                                    self.result = nil
                                }) {
                                    Text("Run Again")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.gray.opacity(0.2))
                                        .foregroundColor(.primary)
                                        .cornerRadius(12)
                                }
                            }
                            .padding(.top)
                        }
                        .padding()
                    }
                    
                } else {
                    // Initial state
                    VStack(spacing: 24) {
                        Image(systemName: "sparkles.rectangle.stack.fill")
                            .font(.system(size: 80))
                            .foregroundColor(.purple)
                        
                        VStack(spacing: 12) {
                            Text("Super Housekeeping")
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("Extract and organize all people from your journal")
                                .font(.body)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                        }
                        
                        VStack(alignment: .leading, spacing: 16) {
                            FeatureRow(icon: "person.crop.circle.badge.checkmark", title: "Identify People", description: "Find all people mentioned")
                            FeatureRow(icon: "bubble.left.and.bubble.right", title: "Extract Interactions", description: "Log all conversations")
                            FeatureRow(icon: "doc.text", title: "Generate Summaries", description: "AI-powered person summaries")
                            FeatureRow(icon: "arrow.triangle.2.circlepath", title: "Remove Duplicates", description: "Clean duplicate entries")
                            FeatureRow(icon: "folder", title: "Organize Files", description: "Create person files")
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(12)
                        
                        Button(action: {
                            runSuperHousekeeping()
                        }) {
                            HStack {
                                Image(systemName: "play.fill")
                                Text("Run Super Housekeeping")
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.purple)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Super Housekeeping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func runSuperHousekeeping() {
        isRunning = true
        progressMessage = "Analyzing journal..."
        progressLog = []
        
        Task {
            let peopleManager = PeopleManager(fileManager: appState.fileManager)
            let service = SuperHousekeepingService(
                fileManager: appState.fileManager,
                peopleManager: peopleManager,
                claudeService: appState.claudeService
            )
            
            // Set up progress callback
            service.onProgress = { message in
                Task { @MainActor in
                    self.progressMessage = message
                    self.progressLog.append(message)
                }
            }
            
            let housekeepingResult = await service.runSuperHousekeeping()
            
            await MainActor.run {
                self.result = housekeepingResult
                self.isRunning = false
            }
        }
    }
}
