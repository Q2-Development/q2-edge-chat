import SwiftUI

struct ModelSettingsView: View {
    @Binding var settings: ModelSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Generation Parameters")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.2f", settings.temperature))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(settings.temperature) },
                            set: { settings.temperature = Float($0) }
                        ), in: 0.1...2.0, step: 0.1)
                        Text("Controls randomness. Lower = more focused, Higher = more creative")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Max Tokens")
                            Spacer()
                            Text("\(settings.maxTokens)")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(settings.maxTokens) },
                            set: { settings.maxTokens = Int32($0) }
                        ), in: 50...1000, step: 10)
                        Text("Maximum response length in tokens")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Top P")
                            Spacer()
                            Text(String(format: "%.2f", settings.topP))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(settings.topP) },
                            set: { settings.topP = Float($0) }
                        ), in: 0.1...1.0, step: 0.05)
                        Text("Nucleus sampling. Controls diversity of word choices")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Top K")
                            Spacer()
                            Text("\(settings.topK)")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(settings.topK) },
                            set: { settings.topK = Int32($0) }
                        ), in: 1...100, step: 1)
                        Text("Limits word choices to top K most likely tokens")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Repeat Penalty")
                            Spacer()
                            Text(String(format: "%.2f", settings.repeatPenalty))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: Binding(
                            get: { Double(settings.repeatPenalty) },
                            set: { settings.repeatPenalty = Float($0) }
                        ), in: 1.0...1.5, step: 0.05)
                        Text("Penalty for repeating tokens. Higher = less repetition")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section(header: Text("System Prompt")) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $settings.systemPrompt)
                            .frame(minHeight: 100)
                        Text("Instructions that guide the model's behavior throughout the conversation")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Section {
                    Button("Reset to Defaults") {
                        settings = .default
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Model Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}