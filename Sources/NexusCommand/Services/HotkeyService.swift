import AppKit
import Carbon
import os

@MainActor @Observable
final class HotkeyService {
    private static let logger = Logger(subsystem: "com.nexuscommand", category: "hotkey")

    private(set) var currentHotkey: HotkeyCombo?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var carbonHotKeyRef: EventHotKeyRef?
    private var notificationObserver: (any NSObjectProtocol)?
    private var handler: (() -> Void)?

    func register(hotkey: HotkeyCombo, handler: @escaping () -> Void) throws {
        unregister()
        self.handler = handler

        // Try Carbon API first — does NOT require Accessibility permission
        do {
            try registerCarbonHotKey(hotkey)
            currentHotkey = hotkey
            Self.logger.info("Hotkey registered via Carbon: \(hotkey.displayString)")
            return
        } catch {
            Self.logger.warning("Carbon hotkey failed: \(error), falling back to NSEvent monitor")
        }

        // Fallback: NSEvent global monitor (needs Accessibility permission)
        if !isAccessibilityGranted() {
            Self.logger.warning("Accessibility not granted — global monitor may not receive events")
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                if event.keyCode == hotkey.keyCode,
                   event.modifierFlags.intersection(.deviceIndependentFlagsMask) == hotkey.modifierFlags {
                    self.handler?()
                }
            }
        }

        // Also monitor local events (when our app is focused)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == hotkey.keyCode,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask) == hotkey.modifierFlags {
                Task { @MainActor in self.handler?() }
                return nil
            }
            return event
        }

        currentHotkey = hotkey
        Self.logger.info("Hotkey registered via NSEvent monitor: \(hotkey.displayString)")
    }

    func unregister() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil

        if let notificationObserver {
            NotificationCenter.default.removeObserver(notificationObserver)
        }
        notificationObserver = nil

        if let carbonHotKeyRef {
            UnregisterEventHotKey(carbonHotKeyRef)
        }
        carbonHotKeyRef = nil

        currentHotkey = nil
        handler = nil
        Self.logger.info("Hotkey unregistered")
    }

    private func registerCarbonHotKey(_ hotkey: HotkeyCombo) throws {
        var carbonModifiers: UInt32 = 0
        let flags = hotkey.modifierFlags
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }

        let hotKeyID = EventHotKeyID(signature: OSType(0x4E58_434D), id: 1) // "NXCM"
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode),
            carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == OSStatus(eventHotKeyExistsErr) {
            throw HotkeyError.hotkeyConflict
        }
        guard status == noErr, let ref else {
            throw HotkeyError.hotkeyConflict
        }

        carbonHotKeyRef = ref

        // Install Carbon event handler for hot key pressed
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            // Post notification that the global handler will pick up
            NotificationCenter.default.post(name: .nexusCarbonHotkeyPressed, object: nil)
            return noErr
        }, 1, &eventType, nil, nil)

        notificationObserver = NotificationCenter.default.addObserver(forName: .nexusCarbonHotkeyPressed, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.handler?()
            }
        }
    }

    private func isAccessibilityGranted() -> Bool {
        let key = "AXTrustedCheckOptionPrompt" as CFString as String
        let options = [key: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString as String
        let options = [key: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}

extension Notification.Name {
    static let nexusCarbonHotkeyPressed = Notification.Name("com.nexuscommand.carbonHotkeyPressed")
}
