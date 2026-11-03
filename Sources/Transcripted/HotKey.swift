import Carbon

@MainActor
final class HotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?

    func register() throws {
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<HotKey>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in hotKey.action?() }
            return noErr
        }, 1, &event, pointer, &handler)
        guard installed == noErr else { throw AppFailure("Could not install the keyboard shortcut.") }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(cmdKey | shiftKey), EventHotKeyID(signature: 0x54524344, id: 1), GetApplicationEventTarget(), 0, &reference)
        guard status == noErr else { throw AppFailure("⌘⇧R is already in use. Use the menu-bar recording button.") }
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
