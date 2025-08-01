import SwiftUI
import UniformTypeIdentifiers

struct ExportChatView: View {
    let session: ChatSession
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFormat: ExportFormat = .json
    @State private var showingShareSheet = false
    @State private var exportURL: URL?
    
    enum ExportFormat: String, CaseIterable {
        case json = "JSON"
        case txt = "TXT"
        
        var fileExtension: String {
            switch self {
            case .json: return "json"
            case .txt: return "txt"
            }
        }
        
        var contentType: UTType {
            switch self {
            case .json: return .json
            case .txt: return .plainText
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Export Format")
                        .font(.headline)
                    
                    Picker("Format", selection: $selectedFormat) {
                        ForEach(ExportFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Chat Preview")
                        .font(.headline)
                    
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Title: \(session.title)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Text("Created: \(session.createdAt, formatter: dateFormatter)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Model: \(session.modelID)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Messages: \(session.messages.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Divider()
                            
                            if selectedFormat == .json {
                                Text(generateJSONPreview())
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                            } else {
                                Text(generateTXTPreview())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                Button("Export Chat") {
                    exportChat()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .navigationTitle("Export Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = exportURL {
                ShareSheet(activityItems: [url])
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
    
    private func generateJSONPreview() -> String {
        let preview = generateJSONContent()
        let lines = preview.components(separatedBy: .newlines)
        return lines.prefix(10).joined(separator: "\n") + (lines.count > 10 ? "\n..." : "")
    }
    
    private func generateTXTPreview() -> String {
        let preview = generateTXTContent()
        let lines = preview.components(separatedBy: .newlines)
        return lines.prefix(15).joined(separator: "\n") + (lines.count > 15 ? "\n..." : "")
    }
    
    private func generateJSONContent() -> String {
        let exportData: [String: Any] = [
            "title": session.title,
            "id": session.id.uuidString,
            "createdAt": ISO8601DateFormatter().string(from: session.createdAt),
            "modelID": session.modelID,
            "modelSettings": [
                "temperature": session.modelSettings.temperature,
                "maxTokens": session.modelSettings.maxTokens,
                "topP": session.modelSettings.topP,
                "topK": session.modelSettings.topK,
                "repeatPenalty": session.modelSettings.repeatPenalty,
                "systemPrompt": session.modelSettings.systemPrompt
            ],
            "messages": session.messages.map { message in
                [
                    "id": message.id.uuidString,
                    "speaker": message.speaker == .user ? "user" : "assistant",
                    "text": message.text,
                    "timestamp": ISO8601DateFormatter().string(from: message.timestamp)
                ]
            }
        ]
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8) ?? ""
        } catch {
            return "Error generating JSON: \(error.localizedDescription)"
        }
    }
    
    private func generateTXTContent() -> String {
        var content = """
        Chat Export
        ===========
        
        Title: \(session.title)
        Created: \(dateFormatter.string(from: session.createdAt))
        Model: \(session.modelID)
        Total Messages: \(session.messages.count)
        
        Model Settings:
        - Temperature: \(session.modelSettings.temperature)
        - Max Tokens: \(session.modelSettings.maxTokens)
        - Top P: \(session.modelSettings.topP)
        - Top K: \(session.modelSettings.topK)
        - Repeat Penalty: \(session.modelSettings.repeatPenalty)
        """
        
        if !session.modelSettings.systemPrompt.isEmpty {
            content += "\n- System Prompt: \(session.modelSettings.systemPrompt)"
        }
        
        content += "\n\nConversation:\n" + String(repeating: "=", count: 50) + "\n\n"
        
        for message in session.messages {
            let speaker = message.speaker == .user ? "You" : "Assistant"
            let timestamp = DateFormatter().apply {
                $0.timeStyle = .short
                $0.dateStyle = .none
            }.string(from: message.timestamp)
            
            content += "[\(timestamp)] \(speaker):\n\(message.text)\n\n"
        }
        
        return content
    }
    
    private func exportChat() {
        let content: String
        let filename: String
        
        switch selectedFormat {
        case .json:
            content = generateJSONContent()
            filename = "\(session.title.replacingOccurrences(of: " ", with: "_"))_\(formatDateForFilename(session.createdAt)).json"
        case .txt:
            content = generateTXTContent()
            filename = "\(session.title.replacingOccurrences(of: " ", with: "_"))_\(formatDateForFilename(session.createdAt)).txt"
        }
        
        guard let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return
        }
        
        let fileURL = documentsDirectory.appendingPathComponent(filename)
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            exportURL = fileURL
            showingShareSheet = true
        } catch {
            print("Export error: \(error)")
        }
    }
    
    private func formatDateForFilename(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm"
        return formatter.string(from: date)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension DateFormatter {
    func apply(_ closure: (DateFormatter) -> Void) -> DateFormatter {
        closure(self)
        return self
    }
}