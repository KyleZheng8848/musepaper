import Foundation

/// In-app changelog — keep locked with `CHANGELOG.md` and `Packaging/VERSION`.
struct ChangelogEntry: Identifiable, Equatable, Sendable {
    var version: String
    var date: String
    var highlights: [String]
    var id: String { "\(version)-\(date)" }
}

enum AppChangelog {
    static let entries: [ChangelogEntry] = [
                                                                                                                                                                                                                                                                                                                                                                                        ChangelogEntry(
            version: "0.5.40",
            date: "2026-10-20",
            highlights: [
                "SofunAI 工作室出品标识与原生矢量 logo",
                "新增独立关于窗口、应用菜单入口和开源主页链接"
            ]
        )
    ]

    static var latest: ChangelogEntry? { entries.first }
}
