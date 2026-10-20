import AppKit
import SwiftUI

@main
struct MusepaperApp: App {
    @NSApplicationDelegateAdaptor(MusepaperAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

/// Musepaper is distributed as a small hand-built app bundle rather than through
/// Xcode. Owning the main NSWindow explicitly gives relaunches deterministic
/// behavior even after the user previously closed the last window.
@MainActor
final class MusepaperAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NotificationCenter.default.addObserver(
            forName: .musepaperOpenMainWindow, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.showMainWindow() }
        }
        showMainWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showMainWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        // No fullSizeContentView: content must stay inside the content view so the
        // bottom workbench cannot be laid out under the window chrome and clipped.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = AppVersion.windowTitle
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1100, height: 800)
        window.center()
        window.contentView = NSHostingView(rootView: StudioView())
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
