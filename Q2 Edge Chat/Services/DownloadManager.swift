import Foundation
import Combine
import UserNotifications

struct DownloadState: Equatable {
    enum Status: Equatable {
        case idle
        case running
        case completed
        case failed(String)
        case cancelled
    }

    var bytesWritten: Int64 = 0
    var totalBytes: Int64 = 0
    var progress: Double = 0
    var estimatedTimeRemaining: TimeInterval = 0
    var status: Status = .idle
}

final class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()

    @Published private(set) var states: [String: DownloadState] = [:]

    private var session: URLSession!
    private var tasksByModelId: [String: URLSessionDownloadTask] = [:]
    private var resumeDataByModelId: [String: Data] = [:]
    private var lastUpdateTimeByModelId: [String: TimeInterval] = [:]
    private var lastBytesByModelId: [String: Int64] = [:]
    private let notificationCenter = UNUserNotificationCenter.current()
    private var lastNotifyTimeByModelId: [String: TimeInterval] = [:]

    var backgroundCompletionHandler: (() -> Void)?

    private override init() {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: "com.q2edge.downloads")
        config.sessionSendsLaunchEvents = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 7 * 24 * 3600
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func isDownloading(_ modelId: String) -> Bool {
        return tasksByModelId[modelId] != nil
    }

    func progress(for modelId: String) -> Double {
        return states[modelId]?.progress ?? 0
    }

    func startHFDownload(model: HFModel, token: String? = nil) async throws {
        guard let sibling = model.siblings.first(where: { $0.rfilename.hasSuffix(".gguf") || $0.rfilename.hasSuffix(".bin") }) else {
            throw URLError(.fileDoesNotExist)
        }
        let encoded = model.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model.id
        guard let remoteURL = URL(string: "https://huggingface.co/\(encoded)/resolve/main/\(sibling.rfilename)") else {
            throw URLError(.badURL)
        }

        let modelManager = ModelManager()
        let destURL = try await modelManager.buildLocalModelURL(modelID: model.id, filename: sibling.rfilename)
        try FileManager.default.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        var request = URLRequest(url: remoteURL)
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let task = session.downloadTask(with: request)
        task.taskDescription = "\(model.id)|\(destURL.path)"
        tasksByModelId[model.id] = task
        states[model.id] = DownloadState(bytesWritten: 0, totalBytes: 0, progress: 0, estimatedTimeRemaining: 0, status: .running)
        lastUpdateTimeByModelId[model.id] = Date().timeIntervalSince1970
        lastBytesByModelId[model.id] = 0
        task.resume()
        requestAuthorizationIfNeeded()
        postStartNotification(modelId: model.id)
    }

    func cancel(modelId: String) {
        guard let task = tasksByModelId[modelId] else { return }
        task.cancel { data in
            if let data = data { self.resumeDataByModelId[modelId] = data }
        }
        tasksByModelId.removeValue(forKey: modelId)
        states[modelId]?.status = .cancelled
    }

    func resume(modelId: String) {
        if let data = resumeDataByModelId[modelId] {
            let task = session.downloadTask(withResumeData: data)
            task.taskDescription = tasksByModelId[modelId]?.taskDescription
            tasksByModelId[modelId] = task
            states[modelId]?.status = .running
            task.resume()
            resumeDataByModelId.removeValue(forKey: modelId)
        }
    }

    private func requestAuthorizationIfNeeded() {
        notificationCenter.getNotificationSettings { settings in
            if settings.authorizationStatus == .notDetermined {
                self.notificationCenter.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
            }
        }
    }

    private func postStartNotification(modelId: String) {
        let content = UNMutableNotificationContent()
        content.title = "Downloading model"
        content.body = modelId
        content.categoryIdentifier = "DOWNLOAD"
        content.threadIdentifier = "download"
        content.userInfo = ["modelId": modelId]
        let req = UNNotificationRequest(identifier: "download-start-\(modelId)", content: content, trigger: nil)
        notificationCenter.add(req)
    }

    private func postCompletionNotification(modelId: String, success: Bool) {
        let content = UNMutableNotificationContent()
        content.title = success ? "Download completed" : "Download failed"
        content.body = modelId
        content.threadIdentifier = "download"
        content.userInfo = ["modelId": modelId]
        let req = UNNotificationRequest(identifier: "download-finish-\(modelId)", content: content, trigger: nil)
        notificationCenter.add(req)
    }

    private func postProgressNotification(modelId: String, progress: Double, eta: TimeInterval) {
        let now = Date().timeIntervalSince1970
        let last = lastNotifyTimeByModelId[modelId] ?? 0
        if now - last < 1 { return }
        lastNotifyTimeByModelId[modelId] = now
        let percent = Int((progress * 100).rounded())
        let minutes = Int(eta / 60)
        let seconds = Int(eta.truncatingRemainder(dividingBy: 60))
        let etaText = minutes > 0 ? "~\(minutes)m \(seconds)s" : "~\(seconds)s"

        let content = UNMutableNotificationContent()
        content.title = "Downloading… \(percent)%"
        content.body = "\(modelId) • ETA \(etaText)"
        content.categoryIdentifier = "DOWNLOAD"
        content.threadIdentifier = "download"
        content.userInfo = ["modelId": modelId]
        let req = UNNotificationRequest(identifier: "download-\(modelId)", content: content, trigger: nil)
        notificationCenter.add(req)
    }
}

extension DownloadManager: URLSessionDownloadDelegate, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let desc = downloadTask.taskDescription else { return }
        let parts = desc.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let modelId = parts[0]
        var state = states[modelId] ?? DownloadState()
        state.bytesWritten = totalBytesWritten
        state.totalBytes = totalBytesExpectedToWrite
        if totalBytesExpectedToWrite > 0 {
            state.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        }
        let now = Date().timeIntervalSince1970
        let lastTime = lastUpdateTimeByModelId[modelId] ?? now
        let lastBytes = lastBytesByModelId[modelId] ?? 0
        let dt = max(now - lastTime, 0.001)
        let db = totalBytesWritten - lastBytes
        if db > 0 {
            let speed = Double(db) / dt
            let remaining = max(Double(totalBytesExpectedToWrite - totalBytesWritten), 0)
            state.estimatedTimeRemaining = speed > 0 ? remaining / speed : 0
        }
        lastUpdateTimeByModelId[modelId] = now
        lastBytesByModelId[modelId] = totalBytesWritten
        state.status = .running
        DispatchQueue.main.async {
            self.states[modelId] = state
        }
        postProgressNotification(modelId: modelId, progress: state.progress, eta: state.estimatedTimeRemaining)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let desc = downloadTask.taskDescription else { return }
        let parts = desc.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let modelId = parts[0]
        let destPath = parts[1]
        let destURL = URL(fileURLWithPath: destPath)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.moveItem(at: location, to: destURL)
            let entry = ManifestEntry(id: modelId, localURL: destURL, downloadedAt: Date())
            Task {
                do {
                    let store = try ManifestStore()
                    try await store.add(entry)
                } catch {}
            }
            DispatchQueue.main.async {
                var state = self.states[modelId] ?? DownloadState()
                state.status = .completed
                state.progress = 1
                self.states[modelId] = state
            }
            tasksByModelId.removeValue(forKey: modelId)
            resumeDataByModelId.removeValue(forKey: modelId)
            lastUpdateTimeByModelId.removeValue(forKey: modelId)
            lastBytesByModelId.removeValue(forKey: modelId)
            postCompletionNotification(modelId: modelId, success: true)
        } catch {
            DispatchQueue.main.async {
                var state = self.states[modelId] ?? DownloadState()
                state.status = .failed(error.localizedDescription)
                self.states[modelId] = state
            }
            postCompletionNotification(modelId: modelId, success: false)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let desc = task.taskDescription else { return }
        let parts = desc.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return }
        let modelId = parts[0]
        if let err = error as NSError? {
            if err.domain == NSURLErrorDomain && err.code == NSURLErrorCancelled {
                return
            }
            DispatchQueue.main.async {
                var state = self.states[modelId] ?? DownloadState()
                state.status = .failed(err.localizedDescription)
                self.states[modelId] = state
            }
            postCompletionNotification(modelId: modelId, success: false)
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletionHandler?()
            self.backgroundCompletionHandler = nil
        }
    }
}

