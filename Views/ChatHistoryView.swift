import SwiftUI

struct ChatHistoryView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(appState.chatSessions) { session in
                    Button(action: {
                        appState.switchToSession(session.id)
                        dismiss()
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(session.title)
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                
                                Spacer()
                                
                                if session.id == appState.currentSessionId {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            Text(session.preview)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                            
                            HStack {
                                Text("\(session.messages.count) messages")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Text(formatDate(session.updatedAt))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            appState.deleteSession(session)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Chat History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        appState.createNewSession()
                        dismiss()
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
