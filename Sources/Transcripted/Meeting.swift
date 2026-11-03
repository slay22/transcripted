import Foundation

enum MeetingLanguage: String, Codable, CaseIterable, Identifiable {
    case english = "en-US", french = "fr-FR", german = "de-DE"
    var id: String { rawValue }
    var name: String {
        switch self { case .english: "English"; case .french: "French"; case .german: "German" }
    }
}

struct TranscriptSegment: Codable, Identifiable {
    var id = UUID()
    var seconds: Double
    var text: String
}

struct Meeting: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var title: String
    var language: MeetingLanguage
    var includesSystemAudio: Bool
    var duration: Double = 0
    var segments: [TranscriptSegment] = []
    var summary = ""
    var issue: String?
    mutating func updateDetails(title: String, date: Date) throws {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw AppFailure("Enter a meeting name.") }
        self.title = name
        self.date = date
    }
    var transcript: String { segments.map(\.text).joined(separator: "\n") }
    var markdown: String {
        "# \(title)\n\n\(date.formatted()) · \(language.name)\n\n## Summary\n\n\(summary.isEmpty ? "Summary not generated." : summary)\n\n## Transcript\n\n" + segments.map {
            "[\(Self.timestamp($0.seconds))] \($0.text)"
        }.joined(separator: "\n\n")
    }
    static func timestamp(_ seconds: Double) -> String {
        let value = max(0, Int(seconds))
        return String(format: "%02d:%02d", value / 60, value % 60)
    }
}

struct AppFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

struct MeetingStore {
    let root: URL
    init(root: URL? = nil) throws {
        self.root = try root ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Transcripted/Meetings", isDirectory: true)
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }
    func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func delete(_ id: UUID) throws {
        try FileManager.default.removeItem(at: directory(id))
    }
    func save(_ meeting: Meeting) throws {
        let folder = directory(meeting.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meeting).write(to: folder.appendingPathComponent("meeting.json"), options: .atomic)
    }
    func load() throws -> [Meeting] {
        try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
            .map { try JSONDecoder().decode(Meeting.self, from: Data(contentsOf: $0.appendingPathComponent("meeting.json"))) }
            .sorted { $0.date > $1.date }
    }
}

enum TextChunks {
    // Bound UTF-8 bytes, rather than word count, to leave room for multilingual output.
    static func split(_ text: String, limit: Int = 2400) -> [String] {
        precondition(limit >= 4)
        var chunks: [String] = [], current = ""
        var bytes = 0
        for character in text {
            let piece = String(character)
            if bytes + piece.utf8.count > limit && !current.isEmpty {
                chunks.append(current); current = ""; bytes = 0
            }
            current += piece; bytes += piece.utf8.count
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
