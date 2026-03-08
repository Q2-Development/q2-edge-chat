import Foundation

enum DatasetIngestError: Error, LocalizedError {
    case unsupportedFormat
    case emptyDataset
    case invalidJSONLine(Int)
    case invalidJSON
    case unreadableInput

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Only JSON and JSONL datasets are supported."
        case .emptyDataset:
            return "No valid training samples were found in the selected dataset."
        case .invalidJSONLine(let line):
            return "Invalid JSON found at line \(line)."
        case .invalidJSON:
            return "The selected JSON dataset could not be parsed."
        case .unreadableInput:
            return "The selected dataset could not be read."
        }
    }
}

struct PreparedTrainingCorpus: Hashable {
    let train: [String]
    let validate: [String]
    let totalSamples: Int
}

struct DatasetIngestService {
    func loadSamples(from url: URL, maxSamples: Int = 10_000) throws -> [TrainingSample] {
        var samples: [TrainingSample] = []
        samples.reserveCapacity(min(512, maxSamples))

        try forEachSample(from: url, maxSamples: maxSamples) { sample in
            samples.append(sample)
            return true
        }

        guard !samples.isEmpty else {
            throw DatasetIngestError.emptyDataset
        }
        return samples
    }

    func loadTrainingCorpus(from url: URL, config: FineTuneJobConfig) throws -> PreparedTrainingCorpus {
        let maxSamples = recommendedMaxSamples(for: config)
        let formatter = CorpusFormatter(sequenceLength: config.sequenceLength)

        var train: [String] = []
        var validate: [String] = []
        train.reserveCapacity(max(1, Int(Double(maxSamples) * 0.9)))
        validate.reserveCapacity(max(1, Int(Double(maxSamples) * 0.1)))

        var accepted = 0
        try forEachSample(from: url, maxSamples: maxSamples) { sample in
            guard let row = formatter.format(sample: sample) else {
                return true
            }

            accepted += 1
            if accepted % 10 == 0 {
                validate.append(row)
            } else {
                train.append(row)
            }
            return true
        }

        guard accepted > 0 else {
            throw DatasetIngestError.emptyDataset
        }

        if train.isEmpty, !validate.isEmpty {
            train = validate
        }
        if validate.isEmpty, !train.isEmpty {
            validate = train.count > 1 ? [train[train.count - 1]] : train
        }

        return PreparedTrainingCorpus(
            train: train,
            validate: validate,
            totalSamples: accepted
        )
    }

    private func forEachSample(from url: URL, maxSamples: Int, body: (TrainingSample) throws -> Bool) throws {
        let ext = url.pathExtension.lowercased()
        var emitted = 0

        func emit(_ sample: TrainingSample) throws -> Bool {
            guard emitted < maxSamples else { return false }
            emitted += 1
            return try body(sample)
        }

        switch ext {
        case "jsonl":
            try forEachJSONObjectLine(from: url) { object in
                guard let sample = decodeSample(from: object) else {
                    return true
                }
                return try emit(sample)
            }
        case "json":
            guard let stream = InputStream(url: url) else {
                throw DatasetIngestError.unreadableInput
            }
            stream.open()
            defer { stream.close() }

            let object: Any
            do {
                object = try JSONSerialization.jsonObject(with: stream, options: [])
            } catch {
                throw DatasetIngestError.invalidJSON
            }

            if let array = object as? [Any] {
                for item in array {
                    if let sample = decodeSample(from: item), try !emit(sample) {
                        break
                    }
                }
            } else if let sample = decodeSample(from: object) {
                _ = try emit(sample)
            }
        default:
            throw DatasetIngestError.unsupportedFormat
        }
    }

    private func forEachJSONObjectLine(from url: URL, body: (Any) throws -> Bool) throws {
        guard let stream = InputStream(url: url) else {
            throw DatasetIngestError.unreadableInput
        }
        stream.open()
        defer { stream.close() }

        var buffer = Data()
        var lineNumber = 0
        let newline: UInt8 = 0x0A
        let carriageReturn: UInt8 = 0x0D
        var chunk = Array(repeating: UInt8(0), count: 64 * 1024)

        while stream.hasBytesAvailable {
            let readCount = stream.read(&chunk, maxLength: chunk.count)
            if readCount < 0 {
                throw DatasetIngestError.unreadableInput
            }
            if readCount == 0 {
                break
            }

            buffer.append(contentsOf: chunk[0..<readCount])

            while let newlineIndex = buffer.firstIndex(of: newline) {
                let lineData = Data(buffer[..<newlineIndex])
                buffer.removeSubrange(...newlineIndex)
                lineNumber += 1

                let shouldContinue = try decodeJSONObjectLine(
                    lineData,
                    lineNumber: lineNumber,
                    carriageReturn: carriageReturn,
                    body: body
                )
                if !shouldContinue {
                    return
                }
            }
        }

        if !buffer.isEmpty {
            lineNumber += 1
            let shouldContinue = try decodeJSONObjectLine(
                buffer,
                lineNumber: lineNumber,
                carriageReturn: carriageReturn,
                body: body
            )
            if !shouldContinue {
                return
            }
        }
    }

    private func decodeJSONObjectLine(
        _ rawLineData: Data,
        lineNumber: Int,
        carriageReturn: UInt8,
        body: (Any) throws -> Bool
    ) throws -> Bool {
        var lineData = rawLineData

        if let last = lineData.last, last == carriageReturn {
            lineData.removeLast()
        }
        if lineData.isEmpty {
            return true
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: lineData, options: [])
        } catch {
            throw DatasetIngestError.invalidJSONLine(lineNumber)
        }

        return try body(object)
    }

    private func recommendedMaxSamples(for config: FineTuneJobConfig) -> Int {
        let floor = max(64, config.microBatchSize * 16)
        let demand = max(floor, config.steps * config.microBatchSize * 4)
        return min(4_096, demand)
    }

    private struct CorpusFormatter {
        let promptBudget: Int
        let completionBudget: Int

        init(sequenceLength: Int) {
            // ~4 chars/token is a rough approximation for English text.
            let maxChars = max(256, sequenceLength * 4)
            self.promptBudget = max(96, Int(Double(maxChars) * 0.65))
            self.completionBudget = max(64, maxChars - promptBudget)
        }

        func format(sample: TrainingSample) -> String? {
            let prompt = truncated(sample.prompt, maxCharacters: promptBudget)
            let completion = truncated(sample.completion, maxCharacters: completionBudget)
            guard !prompt.isEmpty, !completion.isEmpty else {
                return nil
            }

            return """
            ### Instruction:
            \(prompt)

            ### Response:
            \(completion)
            """
        }

        private func truncated(_ text: String, maxCharacters: Int) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count > maxCharacters else { return trimmed }
            let idx = trimmed.index(trimmed.startIndex, offsetBy: maxCharacters)
            return String(trimmed[..<idx]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func decodeSample(from object: Any) -> TrainingSample? {
        guard let dict = object as? [String: Any] else {
            return nil
        }

        if let prompt = dict["prompt"] as? String,
           let completion = dict["completion"] as? String {
            return normalizedSample(prompt: prompt, completion: completion)
        }

        if let instruction = dict["instruction"] as? String {
            let input = (dict["input"] as? String) ?? ""
            let output = (dict["output"] as? String) ?? ((dict["response"] as? String) ?? "")
            let prompt = input.isEmpty ? instruction : "\(instruction)\n\(input)"
            return normalizedSample(prompt: prompt, completion: output)
        }

        if let text = dict["text"] as? String {
            return normalizedSample(prompt: text, completion: text)
        }

        if let messages = dict["messages"] as? [[String: Any]], !messages.isEmpty {
            let prompt = messages
                .filter { ($0["role"] as? String) != "assistant" }
                .compactMap { $0["content"] as? String }
                .joined(separator: "\n")
            let completion = messages
                .filter { ($0["role"] as? String) == "assistant" }
                .compactMap { $0["content"] as? String }
                .joined(separator: "\n")
            return normalizedSample(prompt: prompt, completion: completion)
        }

        return nil
    }

    private func normalizedSample(prompt: String, completion: String) -> TrainingSample? {
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedCompletion = completion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty, !normalizedCompletion.isEmpty else {
            return nil
        }
        return TrainingSample(prompt: normalizedPrompt, completion: normalizedCompletion)
    }
}
