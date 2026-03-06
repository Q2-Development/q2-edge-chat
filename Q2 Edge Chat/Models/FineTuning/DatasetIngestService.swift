import Foundation

enum DatasetIngestError: Error, LocalizedError {
    case unsupportedFormat
    case emptyDataset
    case invalidJSONLine(Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "Only JSON and JSONL datasets are supported."
        case .emptyDataset:
            return "No valid training samples were found in the selected dataset."
        case .invalidJSONLine(let line):
            return "Invalid JSON found at line \(line)."
        }
    }
}

struct DatasetIngestService {
    func loadSamples(from url: URL, maxSamples: Int = 10_000) throws -> [TrainingSample] {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jsonl":
            return try loadJSONL(from: url, maxSamples: maxSamples)
        case "json":
            return try loadJSON(from: url, maxSamples: maxSamples)
        default:
            throw DatasetIngestError.unsupportedFormat
        }
    }

    private func loadJSONL(from url: URL, maxSamples: Int) throws -> [TrainingSample] {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else {
            throw DatasetIngestError.emptyDataset
        }

        var samples: [TrainingSample] = []
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
        for (idx, line) in lines.enumerated() {
            let lineData = Data(line.utf8)
            let object: Any
            do {
                object = try JSONSerialization.jsonObject(with: lineData)
            } catch {
                throw DatasetIngestError.invalidJSONLine(idx + 1)
            }
            if let sample = decodeSample(from: object) {
                samples.append(sample)
            }
            if samples.count >= maxSamples {
                break
            }
        }

        guard !samples.isEmpty else {
            throw DatasetIngestError.emptyDataset
        }
        return samples
    }

    private func loadJSON(from url: URL, maxSamples: Int) throws -> [TrainingSample] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)

        var samples: [TrainingSample] = []
        if let array = object as? [Any] {
            for item in array {
                if let sample = decodeSample(from: item) {
                    samples.append(sample)
                }
                if samples.count >= maxSamples {
                    break
                }
            }
        } else if let sample = decodeSample(from: object) {
            samples = [sample]
        }

        guard !samples.isEmpty else {
            throw DatasetIngestError.emptyDataset
        }
        return samples
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
