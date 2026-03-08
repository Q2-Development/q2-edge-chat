import SwiftUI
import Combine
import UniformTypeIdentifiers

struct ModernButton: ButtonStyle {
    let color: Color
    let textColor: Color
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundColor(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .padding(.horizontal, 24)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(color)
                    .shadow(color: color.opacity(0.3), radius: 8, x: 0, y: 4)
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}


struct FrontPageView: View {
    @State private var localModels: [ManifestEntry] = []
    @State private var store: ManifestStore?
    @State private var cancellable: AnyCancellable?
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header Section
                    VStack(spacing: 20) {
                        // App Logo/Icon
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 100, height: 100)
                            
                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 40, weight: .medium))
                                .foregroundColor(.white)
                        }
                        .shadow(color: Color.accentColor.opacity(0.3), radius: 20, x: 0, y: 10)
                        
                        VStack(spacing: 8) {
                            Text("Q2 Edge Chat")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            
                            Text("AI-powered conversations on your device")
                                .font(.title3)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.top, 40)
                    
                    // Status Cards
                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            StatusCard(
                                title: "100+",
                                subtitle: "Models",
                                icon: "brain.head.profile",
                                color: .blue
                            )
                            
                            StatusCard(
                                title: "Local",
                                subtitle: "Processing",
                                icon: "iphone",
                                color: .green
                            )
                        }
                        
                        HStack(spacing: 16) {
                            StatusCard(
                                title: "Private",
                                subtitle: "Secure",
                                icon: "lock.shield",
                                color: .orange
                            )
                            
                            StatusCard(
                                title: "Fast",
                                subtitle: "Response",
                                icon: "bolt",
                                color: .purple
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Main Action Buttons
                    VStack(spacing: 16) {
                        NavigationLink(destination: ChatWorkspaceView()) {
                            HStack {
                                Image(systemName: "message.fill")
                                    .font(.title3)
                                Text("Start Chatting")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(ModernButton(color: .accentColor, textColor: .white))
                        
                        NavigationLink(destination: ModelBrowserView()) {
                            HStack {
                                Image(systemName: "brain.head.profile")
                                    .font(.title3)
                                Text("Browse Models")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(ModernButton(color: Color(.systemGray5), textColor: .primary))

                        NavigationLink(destination: FineTuneView()) {
                            HStack {
                                Image(systemName: "slider.horizontal.3")
                                    .font(.title3)
                                Text("Fine-Tune Models")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(ModernButton(color: Color.orange, textColor: .white))

                        NavigationLink(destination: FineTuneRunsView()) {
                            HStack {
                                Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                                    .font(.title3)
                                Text("Fine-Tune Runs")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(ModernButton(color: Color(.systemGray5), textColor: .primary))

                        NavigationLink(destination: AdapterEvaluationView()) {
                            HStack {
                                Image(systemName: "text.magnifyingglass")
                                    .font(.title3)
                                Text("Evaluate Adapter")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(ModernButton(color: Color.teal, textColor: .white))
                    }
                    .padding(.horizontal, 20)
                    
                    Spacer(minLength: 50)
                }
            }
            .background(
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .onAppear {
            loadModels()
        }
    }
    
    private func loadModels() {
        Task {
            do {
                store = try ManifestStore()
                localModels = await store?.all() ?? []
                cancellable = store?.didChange
                    .receive(on: RunLoop.main)
                    .sink { _ in Task { localModels = await store?.all() ?? [] } }
            } catch {
                print("Failed to load models: \(error)")
            }
        }
    }
}

struct StatusCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
            
            Text(title)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
        )
    }
}

struct FrontPageView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FrontPageView()
        }
        .preferredColorScheme(.light)

        NavigationStack {
            FrontPageView()
        }
        .preferredColorScheme(.dark)
    }
}

struct FineTuneView: View {
    @StateObject private var viewModel = FineTuneViewModel()
    @State private var showingPicker = false

    var body: some View {
        Form {
            Section("Model") {
                TextField("MLX model id or local path", text: $viewModel.modelIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Dataset") {
                Text(viewModel.datasetPath.isEmpty ? "No dataset selected" : viewModel.datasetPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Choose JSON/JSONL File") {
                    showingPicker = true
                }
            }

            Section("Method") {
                Picker("Training Method", selection: $viewModel.selectedMethod) {
                    ForEach(TrainingMethod.allCases) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section("Hyperparameters") {
                Stepper("LoRA rank: \(viewModel.loraRank)", value: $viewModel.loraRank, in: 1...128)
                HStack {
                    Text("Learning rate")
                    Spacer()
                    TextField("0.0002", value: $viewModel.learningRate, format: .number.precision(.fractionLength(1...6)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                Stepper("Steps: \(viewModel.steps)", value: $viewModel.steps, in: 10...3000, step: 10)
                Stepper("Seq length: \(viewModel.sequenceLength)", value: $viewModel.sequenceLength, in: 64...2048, step: 64)
                Stepper("Micro-batch: \(viewModel.microBatchSize)", value: $viewModel.microBatchSize, in: 1...8)
            }

            if viewModel.selectedMethod == .galore {
                Section("GaLore") {
                    Stepper("Projection update interval: \(viewModel.projectionUpdateInterval)", value: $viewModel.projectionUpdateInterval, in: 10...1000, step: 10)
                    HStack {
                        Text("Scale factor")
                        Spacer()
                        TextField("0.25", value: $viewModel.scaleFactor, format: .number.precision(.fractionLength(2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                }
            }

            Section("Run Control") {
                HStack(spacing: 12) {
                    Button("Start") {
                        viewModel.startTraining()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isRunning)

                    Button("Stop") {
                        viewModel.stopTraining()
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.isRunning)
                }

                if let progress = viewModel.latestProgress {
                    ProgressView(value: progress.fractionComplete) {
                        Text("Step \(progress.step)/\(progress.totalSteps)")
                    } currentValueLabel: {
                        Text(String(format: "%.3f loss", progress.loss))
                    }
                    Text("Throughput: \(Int(progress.tokensPerSecond)) tok/s")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Peak memory estimate: \(ByteCountFormatter.string(fromByteCount: Int64(progress.estimatedPeakMemoryBytes), countStyle: .memory))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Optimizer memory: \(ByteCountFormatter.string(fromByteCount: Int64(progress.optimizerMemoryBytes), countStyle: .memory))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if progress.method == .galore && progress.baselineOptimizerMemoryBytes > 0 {
                        let saved = max(0, Int64(progress.baselineOptimizerMemoryBytes) - Int64(progress.optimizerMemoryBytes))
                        let pct = (Double(saved) / Double(progress.baselineOptimizerMemoryBytes)) * 100
                        Text(String(format: "GaLore optimizer memory reduction: %.1f%%", pct))
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                    Text("Thermal: \(progress.thermalState.rawValue)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let message = viewModel.statusMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let artifact = viewModel.lastArtifact {
                Section("Last Artifact") {
                    Text(artifact.adapterURL.path)
                        .font(.caption)
                        .lineLimit(2)
                    if #available(iOS 16.0, *) {
                        ShareLink(item: artifact.adapterURL) {
                            Label("Export Adapter", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .navigationTitle("Fine-Tune")
        .fileImporter(
            isPresented: $showingPicker,
            allowedContentTypes: [UTType.json, UTType(filenameExtension: "jsonl") ?? .plainText],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let first = urls.first {
                viewModel.importDataset(from: first)
            }
        }
    }
}

struct FineTuneRunsView: View {
    @StateObject private var viewModel = FineTuneViewModel()

    var body: some View {
        List {
            ForEach(viewModel.runs) { run in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(run.config.baseModelIdentifier)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        Text(run.status.rawValue.capitalized)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(6)
                    }

                    Text("\(run.config.method.displayName) • rank \(run.config.loraRank) • \(run.config.steps) steps")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let progress = run.lastProgress {
                        Text(String(format: "Loss %.3f • %d/%d steps", progress.loss, progress.step, progress.totalSteps))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let artifact = run.artifact {
                        if #available(iOS 16.0, *) {
                            ShareLink(item: artifact.adapterURL) {
                                Label("Export Adapter", systemImage: "square.and.arrow.up")
                                    .font(.caption)
                            }
                        } else {
                            Text(artifact.adapterURL.lastPathComponent)
                                .font(.caption)
                        }
                    }

                    if let errorMessage = run.errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle("Fine-Tune Runs")
        .task {
            await viewModel.reloadRuns()
        }
        .refreshable {
            await viewModel.reloadRuns()
        }
    }
}

struct AdapterEvaluationView: View {
    @StateObject private var viewModel = AdapterEvaluationViewModel()
    @State private var showingAdapterPicker = false

    var body: some View {
        Form {
            Section("Model") {
                TextField("MLX model id or local path", text: $viewModel.modelIdentifier)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section("Adapter") {
                Text(viewModel.adapterPath.isEmpty ? "No adapter selected" : viewModel.adapterPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Button("Choose .safetensors") {
                    showingAdapterPicker = true
                }
            }

            Section("Prompt") {
                TextEditor(text: $viewModel.prompt)
                    .frame(minHeight: 90)
            }

            Section("Generation") {
                Stepper("Max tokens: \(viewModel.maxTokens)", value: $viewModel.maxTokens, in: 16...512, step: 16)
                HStack {
                    Text("Temperature")
                    Spacer()
                    TextField("0.2", value: $viewModel.temperature, format: .number.precision(.fractionLength(1...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                }
            }

            Section("Run") {
                Button {
                    viewModel.runComparison()
                } label: {
                    HStack {
                        if viewModel.isRunning {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(viewModel.isRunning ? "Running..." : "Compare Base vs Adapter")
                    }
                }
                .disabled(viewModel.isRunning)

                if let status = viewModel.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.baseOutput.isEmpty || !viewModel.adaptedOutput.isEmpty {
                Section("Base Output") {
                    ScrollView {
                        Text(viewModel.baseOutput.isEmpty ? "No output yet." : viewModel.baseOutput)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.body.monospaced())
                    }
                    .frame(minHeight: 120)
                }

                Section("Adapter Output") {
                    ScrollView {
                        Text(viewModel.adaptedOutput.isEmpty ? "No output yet." : viewModel.adaptedOutput)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .font(.body.monospaced())
                    }
                    .frame(minHeight: 120)
                }
            }
        }
        .navigationTitle("Adapter Eval")
        .fileImporter(
            isPresented: $showingAdapterPicker,
            allowedContentTypes: [UTType(filenameExtension: "safetensors") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let first = urls.first {
                viewModel.importAdapter(from: first)
            }
        }
    }
}
