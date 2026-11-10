import AppKit
import MacUtilityKit
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let appState: AppState
    private var outsideClickMonitor: Any?
    private var previousApp: NSRunningApplication?

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        super.init()

        popover.behavior = .transient
        popover.contentSize = NSSize(width: MUKTheme.popoverWidth, height: MUKTheme.popoverHeight)
        popover.contentViewController = NSHostingController(rootView: MainPopoverView(appState: appState))
        popover.delegate = self

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "VoxKey")
            button.image?.isTemplate = true
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        appState.refreshPermissions()
        appState.refreshModelStatus()

        // An LSUIElement app must activate to receive key events and outside clicks; otherwise
        // the .transient popover never learns it should dismiss. activate(ignoringOtherApps:) is
        // deprecated and ignored on macOS 26, leaving the popover inactive and its buttons dead;
        // the status-item click is user interaction, so cooperative activate() succeeds.
        NSApp.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKeyAndOrderFront(nil)

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.popover.performClose(nil) }
        }
    }

    private func teardownMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}

extension StatusBarController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        teardownMonitor()
        // Return focus to whatever the user was working in.
        previousApp?.activate()
    }
}
