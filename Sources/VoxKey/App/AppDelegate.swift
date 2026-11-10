import AppKit
import MacUtilityKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var appState: AppState?
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MUKTheme.brand = MUKBrand(
            name: "VoxKey",
            tagline: "Private on-device voice typing",
            symbol: "waveform",
            accent: Color(red: 0.36, green: 0.34, blue: 0.92),
            accentSecondary: Color(red: 0.60, green: 0.34, blue: 0.95))

        let state = AppState()
        // `--demo [--snapshot out.png]`: render a sample state offscreen without starting anything.
        if CommandLine.arguments.contains("--demo") {
            state.showDemoState()
            if let index = CommandLine.arguments.firstIndex(of: "--snapshot"), index + 1 < CommandLine.arguments.count {
                Self.writeSnapshot(of: state, to: CommandLine.arguments[index + 1])
            }
            return
        }
        let statusBarController = StatusBarController(appState: state)
        self.appState = state
        self.statusBarController = statusBarController
        state.start()
    }

    /// Renders the popover offscreen, writes a PNG, and quits.
    private static func writeSnapshot(of state: AppState, to path: String) {
        let view = NSHostingView(rootView: MainPopoverView(appState: state))
        let frame = NSRect(x: 0, y: 0, width: MUKTheme.popoverWidth, height: MUKTheme.popoverHeight)
        view.frame = frame
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stop()
    }
}
