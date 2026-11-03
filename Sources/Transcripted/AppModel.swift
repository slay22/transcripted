import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var meetings: [Meeting] = []
    @Published var selectedID: UUID?
    @Published var language: MeetingLanguage = .english
    @Published var systemAudio = false
    @Published var selectedTab = 0
    @Published var phase = "Ready"
    @Published var isRecording = false
    @Published var isBusy = false
    @Published var recordingStart: Date?
    @Published var error: String?
    @Published var shortcutIssue: String?
    private var store: MeetingStore?
    private let recorder = Recorder()
    private let hotKey = HotKey()
    private var recordingID: UUID?
    private var isManagingMeeting = false
    var selected: Meeting? { meetings.first { $0.id == selectedID } }

    init() {
        do { store = try MeetingStore(); meetings = try store!.load(); selectedID = meetings.first?.id }
        catch { self.error = "Could not open the meeting library: \(error.localizedDescription)" }
        hotKey.action = { [weak self] in self?.toggleRecording() }
        do { try hotKey.register() } catch { shortcutIssue = error.localizedDescription }
        recorder.onFailure = { [weak self] error in
            guard let self, self.isRecording, !self.isBusy else { return }
            self.stopRecording(captureIssue: error.localizedDescription)
        }
    }

    func toggleRecording() {
        guard !isBusy, !isManagingMeeting else { return }
        if isRecording { stopRecording(); return }
        isBusy = true; error = nil; phase = "Starting recording…"
        Task {
            do {
                guard let store else { throw AppFailure("The meeting library is unavailable.") }
                var meeting = Meeting(title: "Meeting · \(Date().formatted(date: .abbreviated, time: .shortened))", language: language, includesSystemAudio: systemAudio)
                meeting.issue = "Recording was interrupted. You can retry transcription from the saved audio."
                try store.save(meeting)
                meetings.insert(meeting, at: 0); selectedID = meeting.id
                try await recorder.start(folder: store.directory(meeting.id), systemAudio: systemAudio)
                recordingID = meeting.id; recordingStart = Date(); isRecording = true; phase = "Recording"
            } catch {
                self.error = error.localizedDescription
                phase = "Ready"
            }
            isBusy = false
        }
    }

    private func stopRecording(captureIssue: String? = nil) {
        guard let id = recordingID else { return }
        isBusy = true; phase = "Saving recording…"
        Task {
            let stopError = await recorder.stop()
            let duration = Date().timeIntervalSince(recordingStart ?? Date())
            isRecording = false; recordingStart = nil; recordingID = nil
            do {
                guard var meeting = meetings.first(where: { $0.id == id }) else { throw AppFailure("Meeting not found.") }
                meeting.duration = duration
                meeting.issue = captureIssue ?? stopError?.localizedDescription
                try save(meeting)
                if let issue = meeting.issue {
                    throw AppFailure("Recording stopped: \(issue) Saved audio is available; use Retry transcription.")
                }
                try await process(id: id)
            } catch { report(error, id: id) }
            isBusy = false; phase = "Ready"
        }
    }

    func retryTranscription() {
        guard let id = selectedID, !isBusy, !isRecording else { return }
        isBusy = true; error = nil
        Task {
            do { try await process(id: id) } catch { report(error, id: id) }
            isBusy = false; phase = "Ready"
        }
    }

    private func process(id: UUID) async throws {
        guard let store, var meeting = meetings.first(where: { $0.id == id }) else { throw AppFailure("Meeting not found.") }
        let folder = store.directory(id)
        let names = meeting.includesSystemAudio ? ["microphone.caf", "system.caf"] : ["microphone.caf"]
        let audio = names.map { folder.appendingPathComponent($0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !audio.isEmpty else { throw AppFailure("No recording was saved. Start a new meeting and check audio permissions.") }
        var segments: [TranscriptSegment] = []
        for (index, file) in audio.enumerated() {
            phase = "Transcribing audio \(index + 1)/\(audio.count)… First use may download language files."
            segments += try await Intelligence.transcribe(file, language: meeting.language)
        }
        meeting.segments = segments.sorted { $0.seconds < $1.seconds }
        meeting.summary = ""
        meeting.issue = nil
        try save(meeting)
        guard !segments.isEmpty else { throw AppFailure("No speech was detected. The audio has been kept for retry.") }
        phase = "Writing summary…"
        meeting.summary = try await Intelligence.summarize(meeting.transcript, language: meeting.language)
        try save(meeting)
    }

    func retrySummary() {
        guard var meeting = selected, !isBusy, !isRecording else { return }
        isBusy = true; error = nil; phase = "Writing summary…"
        Task {
            do {
                meeting.summary = try await Intelligence.summarize(meeting.transcript, language: meeting.language)
                meeting.issue = nil
                try save(meeting)
            } catch { report(error, id: meeting.id) }
            isBusy = false; phase = "Ready"
        }
    }

    private func save(_ meeting: Meeting) throws {
        guard let store else { throw AppFailure("The meeting library is unavailable.") }
        try store.save(meeting)
        if let index = meetings.firstIndex(where: { $0.id == meeting.id }) { meetings[index] = meeting }
    }

    private func report(_ error: Error, id: UUID) {
        self.error = error.localizedDescription
        if var meeting = meetings.first(where: { $0.id == id }) {
            meeting.issue = error.localizedDescription
            do { try save(meeting) } catch { self.error = "\(self.error ?? "")\nCould not save meeting status: \(error.localizedDescription)" }
        }
    }

    func exportSelected() {
        guard let meeting = selected else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.nameFieldStringValue = "Meeting-\(meeting.id.uuidString.prefix(8)).md"
        if panel.runModal() == .OK, let url = panel.url {
            do { try meeting.markdown.write(to: url, atomically: true, encoding: .utf8) }
            catch { self.error = error.localizedDescription }
        }
    }

    func editSelectedMeeting() {
        guard var meeting = selected, !isBusy, !isRecording, !isManagingMeeting else { return }
        isManagingMeeting = true
        defer { isManagingMeeting = false }
        let alert = NSAlert()
        alert.messageText = "Edit meeting details"
        alert.informativeText = "Update the name and date shown in your library and future exports."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let name = NSTextField(string: meeting.title)
        name.placeholderString = "Meeting name"
        name.setAccessibilityLabel("Meeting name")
        let date = NSDatePicker()
        date.datePickerElements = [.yearMonthDay, .hourMinute]
        date.datePickerStyle = .textFieldAndStepper
        date.dateValue = meeting.date
        date.setAccessibilityLabel("Meeting date and time")
        let fields = NSStackView(views: [NSTextField(labelWithString: "Name"), name, NSTextField(labelWithString: "Date and time"), date])
        fields.orientation = .vertical
        fields.alignment = .leading
        fields.spacing = 8
        fields.frame = NSRect(x: 0, y: 0, width: 360, height: 120)
        name.widthAnchor.constraint(equalToConstant: 360).isActive = true
        alert.accessoryView = fields
        alert.window.initialFirstResponder = name
        while alert.runModal() == .alertFirstButtonReturn {
            do {
                try meeting.updateDetails(title: name.stringValue, date: date.dateValue)
                try save(meeting)
                meetings.sort { $0.date > $1.date }
                return
            } catch {
                alert.informativeText = error.localizedDescription
            }
        }
    }

    func deleteSelectedMeeting() {
        guard let meeting = selected, let store, !isBusy, !isRecording, !isManagingMeeting else { return }
        isManagingMeeting = true
        defer { isManagingMeeting = false }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(meeting.title)”?"
        alert.informativeText = "This permanently deletes this meeting’s transcript, summary, and saved audio from this Mac. Exported copies are not affected. This cannot be undone."
        alert.addButton(withTitle: "Cancel")
        let deleteButton = alert.addButton(withTitle: "Delete meeting")
        deleteButton.hasDestructiveAction = true
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        do {
            try store.delete(meeting.id)
            let index = meetings.firstIndex { $0.id == meeting.id } ?? 0
            meetings.removeAll { $0.id == meeting.id }
            selectedID = meetings.isEmpty ? nil : meetings[min(index, meetings.count - 1)].id
            error = nil
        } catch { self.error = "Could not delete the meeting: \(error.localizedDescription)" }
    }

    func revealLibrary() {
        guard let store else { return }
        NSWorkspace.shared.open(store.root)
    }

    func revealAudio() {
        guard let store, let id = selectedID else { return }
        NSWorkspace.shared.open(store.directory(id))
    }
}
