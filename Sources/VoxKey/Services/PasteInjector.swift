import AppKit
import Foundation

final class PasteInjector {
    func paste(_ text: String, sendEnterAfterPaste: Bool = false) throws {
        guard AXIsProcessTrusted() else {
            throw VoxKeyError.pastePermissionMissing
        }

        let pasteboard = NSPasteboard.general
        let preserved = PasteboardSnapshot.capture(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        sendPasteShortcut()

        if sendEnterAfterPaste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                self.sendReturnKey()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            preserved.restore(to: pasteboard)
        }
    }

    /// Types arbitrary text at the cursor (used for live, as-you-speak insertion).
    /// Uses a private event source and clears flags so the modifier keys the user is
    /// physically holding for push-to-talk (e.g. Fn+Control) don't corrupt the keystrokes.
    func typeText(_ text: String) {
        guard !text.isEmpty, AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .privateState)
        let utf16 = Array(text.utf16)
        utf16.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
            down?.flags = []
            down?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            up?.flags = []
            up?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: base)
            up?.post(tap: .cghidEventTap)
        }
    }

    /// Sends `count` backspaces (used to replace volatile live text as it's revised).
    func deleteBackward(_ count: Int) {
        guard count > 0, AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .privateState)
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: true)
            down?.flags = []
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: source, virtualKey: 51, keyDown: false)
            up?.flags = []
            up?.post(tap: .cghidEventTap)
        }
    }

    func sendReturn() {
        sendReturnKey()
    }

    private func sendPasteShortcut() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func sendReturnKey() {
        let source = CGEventSource(stateID: .privateState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false)
        keyDown?.flags = []
        keyUp?.flags = []
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

private struct PasteboardSnapshot {
    let items: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let captured: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return values
        } ?? []
        return PasteboardSnapshot(items: captured)
    }

    func restore(to pasteboard: NSPasteboard) {
        guard !items.isEmpty else { return }
        pasteboard.clearContents()
        let restored = items.map { values in
            let item = NSPasteboardItem()
            for (type, data) in values {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}
