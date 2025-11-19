import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var claudeApiKey: String = ""
    @State private var openAIApiKey: String = ""
    @State private var selectedModel: Settings.ClaudeModel = .sonnet35
    @State private var autoAddToCalendar: Bool = false
    @State private var storeRawAudio: Bool = true
    @State private var autoResumePendingUtterances: Bool = true
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("API Keys")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Claude API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter Claude API key", text: $claudeApiKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("OpenAI API Key")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        SecureField("Enter OpenAI API key", text: $openAIApiKey)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    
                    Button("Save API Keys") {
                        saveAPIKeys()
                    }
                    .frame(maxWidth: .infinity)
                }
                
                Section(header: Text("Claude Model")) {
                    ForEach(Settings.ClaudeModel.allCases, id: \.self) { model in
                        Button(action: {
                            selectedModel = model
                            saveSettings()
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(model.displayName)
                                        .foregroundColor(.primary)
                                    
                                    Text(model.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if selectedModel == model {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                
                Section(header: Text("Behavior")) {
                    Toggle("Auto-add to Calendar/Reminders", isOn: $autoAddToCalendar)
                        .onChange(of: autoAddToCalendar) { _ in saveSettings() }
                    
                    Text("When enabled, calendar events and reminders will be added automatically. When disabled, you'll be asked for confirmation.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Storage")) {
                    Toggle("Store Raw Audio", isOn: $storeRawAudio)
                        .onChange(of: storeRawAudio) { _ in saveSettings() }
                    
                    Text("Keep original audio recordings for backup and retry purposes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Recovery")) {
                    Toggle("Auto-resume Pending Utterances", isOn: $autoResumePendingUtterances)
                        .onChange(of: autoResumePendingUtterances) { _ in saveSettings() }
                    
                    Text("Automatically process pending utterances when the app launches.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Maintenance")) {
                    NavigationLink("Run Housekeeping Now") {
                        HousekeepingView()
                            .environmentObject(appState)
                    }
                    
                    Text("Check for missing tasks/events, remove duplicates, and ensure data consistency")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("Advanced")) {
                    NavigationLink("System Prompt") {
                        SystemPromptView()
                    }
                    
                    Text("Customize how Claude responds and behaves")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    NavigationLink("View Files in Files App") {
                        FilesInfoView()
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                loadSettings()
            }
        }
    }
    
    private func loadSettings() {
        claudeApiKey = UserDefaults.standard.string(forKey: "claude_api_key") ?? ""
        openAIApiKey = UserDefaults.standard.string(forKey: "openai_api_key") ?? ""
        
        if let modelString = UserDefaults.standard.string(forKey: "claude_model"),
           let model = Settings.ClaudeModel(rawValue: modelString) {
            selectedModel = model
        }
        
        autoAddToCalendar = UserDefaults.standard.bool(forKey: "auto_add_to_calendar")
        storeRawAudio = UserDefaults.standard.bool(forKey: "store_raw_audio")
        autoResumePendingUtterances = UserDefaults.standard.bool(forKey: "auto_resume_pending_utterances")
    }
    
    private func saveAPIKeys() {
        UserDefaults.standard.set(claudeApiKey, forKey: "claude_api_key")
        UserDefaults.standard.set(openAIApiKey, forKey: "openai_api_key")
    }
    
    private func saveSettings() {
        UserDefaults.standard.set(selectedModel.rawValue, forKey: "claude_model")
        UserDefaults.standard.set(autoAddToCalendar, forKey: "auto_add_to_calendar")
        UserDefaults.standard.set(storeRawAudio, forKey: "store_raw_audio")
        UserDefaults.standard.set(autoResumePendingUtterances, forKey: "auto_resume_pending_utterances")
        UserDefaults.standard.synchronize() // Force save
        
        print("✅ Saved Claude model: \(selectedModel.rawValue)")
        
        appState.settings.claudeModel = selectedModel
        appState.settings.autoAddToCalendar = autoAddToCalendar
        appState.settings.storeRawAudio = storeRawAudio
        appState.settings.autoResumePendingUtterances = autoResumePendingUtterances
    }
}

struct FilesInfoView: View {
    var body: some View {
        List {
            Section(header: Text("File Structure")) {
                Text("""
                All files are stored in the app's Documents directory, visible in the Files app under:
                
                On My iPhone › TenX
                
                Directory structure:
                • audio_raw/ - Recorded audio files
                • utterances/ - Daily transcript logs
                • journal/
                  • weeks/ - Weekly detailed and summary files
                  • months/ - Monthly summaries
                  • years/ - Yearly summaries
                • tasks/ - Task list and logs
                • notes/ - Long-term notes
                • backups/ - File version backups
                """)
                .font(.system(.body, design: .monospaced))
                .padding(.vertical)
            }
        }
        .navigationTitle("Files Info")
        .navigationBarTitleDisplayMode(.inline)
    }
}
