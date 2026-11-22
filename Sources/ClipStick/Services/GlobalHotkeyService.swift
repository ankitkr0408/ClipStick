import Carbon.HIToolbox
import Foundation

/// System-wide hotkey via Carbon `RegisterEventHotKey` (needs no Accessibility permission).
final class GlobalHotkeyService {
    var onTrigger: (() -> Void)?
    var onPickColor: (() -> Void)?
    var onRecord: (() -> Void)?
    var onScreenshot: (() -> Void)?
    private var recordKeyRef: EventHotKeyRef?
    private var colorKeyRef: EventHotKeyRef?
    private var screenshotKeyRef: EventHotKeyRef?
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
            InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
                guard let userData else { return noErr }
                let service = Unmanaged<GlobalHotkeyService>.fromOpaque(userData).takeUnretainedValue()
                var id = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                  MemoryLayout<EventHotKeyID>.size, nil, &id)
                DispatchQueue.main.async {
                    switch id.id {
                    case 2: service.onPickColor?()
                    case 3: service.onRecord?()
                    case 4: service.onScreenshot?()
                    default: service.onTrigger?()
                    }
                }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        }
        if colorKeyRef == nil {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x434C_4350), id: 2)
            if RegisterEventHotKey(UInt32(kVK_ANSI_C), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &ref) == noErr { colorKeyRef = ref }
        }
        if recordKeyRef == nil {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x434C_4350), id: 3)
            if RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &ref) == noErr { recordKeyRef = ref }
        }
        if screenshotKeyRef == nil {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x434C_4350), id: 4)
            if RegisterEventHotKey(UInt32(kVK_ANSI_S), UInt32(optionKey), id, GetApplicationEventTarget(), 0, &ref) == noErr { screenshotKeyRef = ref }
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
        if let colorKeyRef { UnregisterEventHotKey(colorKeyRef) }
        if let recordKeyRef { UnregisterEventHotKey(recordKeyRef) }
        if let screenshotKeyRef { UnregisterEventHotKey(screenshotKeyRef) }
        hotKeyRef = nil
        colorKeyRef = nil
        recordKeyRef = nil
        screenshotKeyRef = nil
    }
}
