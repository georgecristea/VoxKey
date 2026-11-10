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
        let statusBarController = StatusBarController(appState: state)
        self.appState = state
        self.statusBarController = statusBarController
        state.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState?.stop()
    }
}
