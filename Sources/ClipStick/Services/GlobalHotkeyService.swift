import Carbon.HIToolbox
import Foundation

/// System-wide hotkey via Carbon `RegisterEventHotKey` (needs no Accessibility permission).
final class GlobalHotkeyService {
    var onTrigger: (() -> Void)?
    private(set) var label = ""

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// Candidates are tried in order; the first one that registers wins.
    private static let candidates: [(label: String, key: Int, mods: Int)] = [
        ("⌥Space", kVK_Space, optionKey),
        ("⌘⇧V", kVK_ANSI_V, cmdKey | shiftKey),
    ]

    @discardableResult
    func register() -> Bool {
        if handlerRef == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
                guard let userData else { return noErr }
                let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { service.onTrigger?() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        }
        for c in Self.candidates {
            let id = EventHotKeyID(signature: OSType(0x434C_4350), id: 1)
            var ref: EventHotKeyRef?
            if RegisterEventHotKey(UInt32(c.key), UInt32(c.mods), id, GetApplicationEventTarget(), 0, &ref) == noErr {
                hotKeyRef = ref
                label = c.label
                return true
            }
        }
        NSLog("ClipStick: could not register a global hotkey")
        return false
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }
}
