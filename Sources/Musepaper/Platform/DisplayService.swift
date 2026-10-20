import AppKit
import Foundation

struct DisplayService {
    func profiles() -> [DisplayProfile] {
        NSScreen.screens.enumerated().map { index, screen in
            let frame = screen.frame
            let scale = screen.backingScaleFactor
            let fallback = index == 0 ? L10n.tr("主显示器") : L10n.tr("显示器 \(index + 1)")
            let localized = screen.localizedName.trimmingCharacters(in: .whitespacesAndNewlines)
            return DisplayProfile(
                id: Self.displayID(index: index),
                name: localized.isEmpty ? fallback : localized,
                width: Int(frame.width * scale),
                height: Int(frame.height * scale),
                scale: scale
            )
        }
    }

    static func profiles(from probes: [DisplayProbe]) -> [DisplayProfile] {
        probes.enumerated().map { index, probe in
            DisplayProfile(
                id: displayID(index: index),
                name: index == 0 ? L10n.tr("主显示器") : L10n.tr("显示器 \(index + 1)"),
                width: probe.width,
                height: probe.height,
                scale: probe.scale
            )
        }
    }

    static func displayID(index: Int) -> String { "screen-\(index)" }

    static func displayID(for screen: NSScreen, in screens: [NSScreen] = NSScreen.screens) -> String? {
        guard let index = screens.firstIndex(where: { $0 === screen }) else { return nil }
        return displayID(index: index)
    }

    static func displayID(containing point: NSPoint, frames: [CGRect]) -> String {
        if let index = frames.firstIndex(where: { $0.contains(point) }) {
            return displayID(index: index)
        }
        return displayID(index: 0)
    }

    static func displayID(containing point: NSPoint, in screens: [NSScreen] = NSScreen.screens) -> String {
        displayID(containing: point, frames: screens.map(\.frame))
    }
}
