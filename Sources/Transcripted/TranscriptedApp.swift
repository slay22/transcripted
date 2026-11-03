import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, model.isRecording || model.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "A meeting is still in progress"
        alert.informativeText = "Stop recording and wait for processing to finish before quitting."
        alert.addButton(withTitle: "Continue")
        alert.runModal()
        return .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct TranscriptedApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Transcripted", id: "library") {
            LibraryView(model: model)
                .onAppear { delegate.model = model }
                .frame(minWidth: 820, minHeight: 580)
        }
        .defaultSize(width: 1040, height: 720)
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Label(model.isRecording ? "Recording" : "Transcripted", systemImage: model.isRecording ? "record.circle.fill" : "waveform")
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(model.phase)
        Button(model.isRecording ? "Stop recording" : "Start recording (⌘⇧R)") { model.toggleRecording() }
            .disabled(model.isBusy)
        Button("Open meeting library") {
            openWindow(id: "library")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Show storage folder", action: model.revealLibrary)
        Divider()
        Button("Quit Transcripted") { NSApp.terminate(nil) }
    }
}

struct LibraryView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Transcripted", systemImage: "waveform").font(.title2.bold())
                Text("A little more present.").foregroundStyle(.secondary)
                Divider()
                Picker("Language", selection: $model.language) {
                    ForEach(MeetingLanguage.allCases) { Text($0.name).tag($0) }
                }
                Picker("Audio", selection: $model.systemAudio) {
                    Text("Microphone").tag(false)
                    Text("Microphone + Mac audio").tag(true)
                }
                Text(model.systemAudio ? "Use headphones to avoid capturing voices twice. All Mac audio is included." : "For conversations in the room, or your own voice.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(action: model.toggleRecording) {
                    Label(model.isRecording ? "Stop & transcribe" : "Record meeting", systemImage: model.isRecording ? "stop.fill" : "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).tint(model.isRecording ? .red : .accentColor)
                .disabled(model.isBusy)
                Text("Global shortcut  ⌘⇧R").font(.caption).foregroundStyle(.secondary)
                if let issue = model.shortcutIssue { Text(issue).font(.caption).foregroundStyle(.orange) }
                if let start = model.recordingStart {
                    HStack { Circle().fill(.red).frame(width: 8, height: 8); Text(start, style: .timer).monospacedDigit() }
                }
                if model.isBusy { ProgressView().controlSize(.small) }
                Text(model.phase).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("MEETINGS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                List(selection: $model.selectedID) {
                    ForEach(model.meetings) { meeting in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(meeting.title).lineLimit(2)
                            Text("\(meeting.language.name) · \(Meeting.timestamp(meeting.duration))").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 5).tag(meeting.id)
                    }
                }.listStyle(.sidebar)
                Button("Show storage folder", action: model.revealLibrary)
                    .font(.caption)
            }
            .padding(20)
            .disabled(model.isRecording && model.isBusy)
            .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 340)
        } detail: {
            VStack(alignment: .leading, spacing: 20) {
                if let error = model.error {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                        Text(error).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button { model.error = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                    }.padding().background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                }
                if let meeting = model.selected {
                    Text(meeting.title).font(.largeTitle.weight(.semibold))
                    Text("\(meeting.date.formatted()) · \(meeting.language.name) · Saved on this Mac").font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Picker("Content", selection: $model.selectedTab) {
                            Text("Summary").tag(0); Text("Transcript").tag(1)
                        }.pickerStyle(.segmented).frame(width: 250)
                        Spacer()
                        Menu {
                            Button("Edit meeting details…", action: model.editSelectedMeeting)
                            Divider()
                            Button("Retry transcription", action: model.retryTranscription)
                            Button("Generate summary", action: model.retrySummary).disabled(meeting.segments.isEmpty)
                            Button("Show meeting folder", action: model.revealAudio)
                            Divider()
                            Button("Delete meeting…", role: .destructive, action: model.deleteSelectedMeeting)
                        } label: { Image(systemName: "ellipsis.circle") }
                        .disabled(model.isBusy || model.isRecording)
                        Button("Export Markdown", action: model.exportSelected)
                    }
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if model.selectedTab == 0 {
                                if meeting.summary.isEmpty {
                                    Text("Your meeting, distilled.").font(.title2.weight(.medium))
                                    Text(meeting.issue ?? "A summary will appear after recording and transcription finish.").foregroundStyle(.secondary)
                                    if let reason = Intelligence.summaryAvailability { Text(reason).foregroundStyle(.secondary) }
                                } else {
                                    Text(LocalizedStringKey(meeting.summary)).font(.body).lineSpacing(6).textSelection(.enabled)
                                    Text("Generated on this Mac. Check important details against the transcript.").font(.caption).foregroundStyle(.secondary)
                                }
                            } else if meeting.segments.isEmpty {
                                Text("The transcript will appear here after recording.").foregroundStyle(.secondary)
                            } else {
                                ForEach(meeting.segments) { segment in
                                    HStack(alignment: .top, spacing: 18) {
                                        Text(Meeting.timestamp(segment.seconds)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48)
                                        Text(segment.text).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                    }
                } else {
                    Spacer()
                    ContentUnavailableView("Be here. Keep the details.", systemImage: "waveform", description: Text("Choose a language, then record your first meeting.\nAudio, transcripts, and summaries stay on your Mac."))
                    Text("Let participants know you’re recording. Language models may need a download on first use.")
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    Spacer()
                }
            }.padding(32)
        }
    }
}
