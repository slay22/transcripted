import Foundation
#if !CORE_CHECK
import XCTest
@testable import Transcripted
#endif

private func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() { throw NSError(domain: "TranscriptedChecks", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}

private func checkMultilingualChunking() throws {
    let input = String(repeating: "English. Français : réunion. Deutsch: Grüße. 👨‍👩‍👧‍👦\n", count: 200)
    let chunks = TextChunks.split(input)
    try require(chunks.count > 1, "Long input should be split")
    try require(chunks.joined() == input, "Chunking must preserve every character")
    try require(chunks.allSatisfy { $0.utf8.count <= 2400 }, "Chunks must respect the byte budget")
    try require(TextChunks.split("").isEmpty, "Empty input should produce no chunks")
}

private func checkPersistence() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try MeetingStore(root: root)
    var meeting = Meeting(title: "Décisions", language: .french, includesSystemAudio: true)
    meeting.segments = [.init(seconds: 75, text: "La prochaine réunion est lundi.")]
    meeting.issue = "Model unavailable"
    try store.save(meeting)
    let loaded = try store.load()
    try require(loaded.count == 1, "A meeting must survive reload")
    let reloaded = loaded[0]
    try require(reloaded.id == meeting.id, "Meeting identity must survive reload")
    try require(reloaded.transcript == meeting.transcript, "Transcript must survive summary failure")
    try require(reloaded.issue == meeting.issue, "Retry status must survive reload")
    try require(reloaded.markdown.contains("[01:15]"), "Export must include timestamps")
    try require(reloaded.markdown.contains("La prochaine réunion est lundi."), "Export must preserve accented text")
    meeting.summary = "Réunion lundi."
    meeting.issue = nil
    try store.save(meeting)
    let updated = try store.load()
    try require(updated.count == 1, "Retry must update, not duplicate the meeting")
    try require(updated[0].summary == "Réunion lundi." && updated[0].issue == nil, "Retry must persist the summary and clear the error")
}

private func checkEditingAndDeletion() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = try MeetingStore(root: root)
    var meeting = Meeting(title: "Original", language: .german, includesSystemAudio: true)
    meeting.segments = [.init(seconds: 4, text: "Guten Morgen.")]
    meeting.summary = "Begrüßung."
    try store.save(meeting)
    let sibling = Meeting(title: "Keep me", language: .english, includesSystemAudio: false)
    try store.save(sibling)
    let audio = Data([1, 2, 3])
    for filename in ["microphone.caf", "system.caf"] {
        try audio.write(to: store.directory(meeting.id).appendingPathComponent(filename))
    }
    do {
        try meeting.updateDetails(title: " \n ", date: Date())
        throw AppFailure("Blank meeting names must be rejected")
    } catch is AppFailure {
        try require(meeting.title == "Original", "Rejected edits must not change the meeting")
    }
    let newDate = Date(timeIntervalSince1970: 123456)
    try meeting.updateDetails(title: "  Weekly planning  ", date: newDate)
    try store.save(meeting)
    let loaded = try store.load().first { $0.id == meeting.id }
    try require(loaded?.title == "Weekly planning" && loaded?.date == newDate, "Edited name and date must survive reload")
    try require(loaded?.transcript == "Guten Morgen." && loaded?.summary == meeting.summary, "Editing details must preserve content")
    try require(loaded?.markdown.hasPrefix("# Weekly planning\n") == true, "Export must use the new name")
    let savedAudio = try Data(contentsOf: store.directory(meeting.id).appendingPathComponent("microphone.caf"))
    try require(savedAudio == audio, "Editing details must preserve audio")
    try store.delete(meeting.id)
    try require(!FileManager.default.fileExists(atPath: store.directory(meeting.id).path), "Deletion must remove metadata and both audio tracks")
    let remaining = try store.load()
    try require(remaining.count == 1 && remaining[0].id == sibling.id, "Deletion must leave other meetings intact")
}

#if CORE_CHECK
@main
struct CoreChecks {
    static func main() throws {
        try checkMultilingualChunking()
        try checkPersistence()
        try checkEditingAndDeletion()
        print("PASS: multilingual chunking, persistence/export, editing, and deletion checks")
    }
}
#else
final class MeetingTests: XCTestCase {
    func testMultilingualChunkingPreservesEveryCharacter() throws { try checkMultilingualChunking() }
    func testMeetingAndTranscriptSurviveReload() throws { try checkPersistence() }
    func testEditingAndDeletion() throws { try checkEditingAndDeletion() }
}
#endif
