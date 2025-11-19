import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            ChatView()
                .tabItem {
                    Label("Chat", systemImage: "message.fill")
                }
                .tag(0)
            
            TasksView()
                .tabItem {
                    Label("Tasks", systemImage: "checklist")
                }
                .tag(1)
            
            JournalView()
                .tabItem {
                    Label("Journal", systemImage: "book.fill")
                }
                .tag(2)
            
            AIItemsView()
                .tabItem {
                    Label("AI Items", systemImage: "sparkles")
                }
                .tag(3)
            
            PeopleView()
                .tabItem {
                    Label("People", systemImage: "person.3.fill")
                }
                .tag(4)
            
            FilesView()
                .tabItem {
                    Label("Files", systemImage: "folder.fill")
                }
                .tag(5)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(6)
        }
    }
}
