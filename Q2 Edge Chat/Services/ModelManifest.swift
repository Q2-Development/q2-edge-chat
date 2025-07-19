//
//  ModelManifest.swift
//  Q2 Edge Chat
//
//  Created by Michael Gathara on 7/19/25.
//

import Foundation

struct ManifestEntry: Codable, Identifiable {
    let id: String
    let localURL: URL
    let downloadedAt: Date
}

actor ManifestStore {
    private let fileURL: URL
    private var entries: [ManifestEntry] = []

    init() throws {
        let fm = FileManager.default
        let support = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        fileURL = support.appendingPathComponent("models.json")
        if fm.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            entries = try JSONDecoder().decode([ManifestEntry].self, from: data)
        }
    }

    func all() -> [ManifestEntry] {
        entries
    }

    func add(_ entry: ManifestEntry) throws {
        entries.append(entry)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }

    func remove(id: String) throws {
        entries.removeAll { $0.id == id }
        let data = try JSONEncoder().encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}

