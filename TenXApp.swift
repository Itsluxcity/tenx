import SwiftUI

@main
struct TenXApp: App {
    @StateObject private var appState = AppState()
    
    init() {
        // Fix: Reset to working model if a non-working one is set
        if let currentModel = UserDefaults.standard.string(forKey: "claude_model") {
            let nonWorkingModels = ["claude-3-5-sonnet-20240620", "claude-3-sonnet-20240229"]
            if nonWorkingModels.contains(currentModel) {
                UserDefaults.standard.set("claude-3-5-haiku-20241022", forKey: "claude_model")
                print("✅ Fixed model to working version: claude-3-5-haiku-20241022")
            }
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    // Request permissions on app launch
                    Task {
                        await appState.requestPermissions()
                        await appState.recoverPendingUtterances()
                    }
                }
        }
    }
}
