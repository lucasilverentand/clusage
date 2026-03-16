import AppKit
import Carbon.HIToolbox

@MainActor @Observable
final class HotkeyManager {
    /// The modifier flags for the dashboard hotkey.
    var modifiers: NSEvent.ModifierFlags {
        didSet { saveHotkey() }
    }

    /// The key code for the dashboard hotkey.
    var keyCode: UInt16 {
        didSet { saveHotkey() }
    }

    /// Whether the user is currently recording a new shortcut.
    var isRecording = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onToggleDashboard: (() -> Void)?

    init() {
        let savedModifiers = UserDefaults.standard.integer(forKey: DefaultsKeys.dashboardHotkeyModifiers)
        let savedKeyCode = UserDefaults.standard.integer(forKey: DefaultsKeys.dashboardHotkeyKeyCode)

        if savedModifiers != 0 || savedKeyCode != 0 {
            self.modifiers = NSEvent.ModifierFlags(rawValue: UInt(savedModifiers))
            self.keyCode = UInt16(savedKeyCode)
        } else {
            // Default: ⌃⌥C
            self.modifiers = [.control, .option]
            self.keyCode = UInt16(kVK_ANSI_C)
        }
    }

    func start(onToggleDashboard: @escaping () -> Void) {
        self.onToggleDashboard = onToggleDashboard
        installMonitor()
        Log.hotkey.info("Hotkey manager started")
    }

    func stop() {
        removeMonitor()
        Log.hotkey.info("Hotkey manager stopped")
    }

    /// Set the hotkey from a key event (used by the recorder).
    func recordKey(from event: NSEvent) {
        guard isRecording else { return }
        let mods = event.modifierFlags.intersection([.control, .option, .command, .shift])
        guard !mods.isEmpty else { return } // Require at least one modifier

        modifiers = mods
        keyCode = event.keyCode
        isRecording = false

        // Reinstall monitor with new key
        removeMonitor()
        installMonitor()

        Log.hotkey.info("Hotkey recorded: keyCode=\(event.keyCode) modifiers=\(mods.rawValue)")
    }

    /// Human-readable description of the current hotkey.
    var hotkeyDescription: String {
        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("⌃") }
        if modifiers.contains(.option) { parts.append("⌥") }
        if modifiers.contains(.shift) { parts.append("⇧") }
        if modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    // MARK: - Private

    private func installMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyEvent(event)
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleKeyEvent(event)
            }
            return event
        }
    }

    private func removeMonitor() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handleKeyEvent(_ event: NSEvent) {
        guard !isRecording else { return }
        let eventMods = event.modifierFlags.intersection([.control, .option, .command, .shift])
        if event.keyCode == keyCode && eventMods == modifiers {
            onToggleDashboard?()
        }
    }

    private func saveHotkey() {
        UserDefaults.standard.set(Int(modifiers.rawValue), forKey: DefaultsKeys.dashboardHotkeyModifiers)
        UserDefaults.standard.set(Int(keyCode), forKey: DefaultsKeys.dashboardHotkeyKeyCode)
    }

    private func keyCodeToString(_ keyCode: UInt16) -> String {
        let mapping: [UInt16: String] = [
            UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C",
            UInt16(kVK_ANSI_D): "D", UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F",
            UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H", UInt16(kVK_ANSI_I): "I",
            UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
            UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O",
            UInt16(kVK_ANSI_P): "P", UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R",
            UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T", UInt16(kVK_ANSI_U): "U",
            UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
            UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
            UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2",
            UInt16(kVK_ANSI_3): "3", UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5",
            UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8",
            UInt16(kVK_ANSI_9): "9",
            UInt16(kVK_Space): "Space", UInt16(kVK_Return): "Return",
            UInt16(kVK_Tab): "Tab", UInt16(kVK_Escape): "Esc",
        ]
        return mapping[keyCode] ?? "Key\(keyCode)"
    }
}
