import Foundation

struct ChangelogEntry: Identifiable, Equatable, Sendable {
    var version: String
    var date: String
    var highlights: [String]
    var id: String { "\(version)-\(date)" }
}

enum AppChangelog {
    static let entries = [
        ChangelogEntry(version: "0.5.63", date: "2026-10-20", highlights: [
            "整合 0.5.62 的随机游走、连续氛围和 LLaDA/Qwen 模型适配",
            "保留中英文选择、SofunAI 关于窗口与开源出品标识",
            "修复洗牌队列的轮内重复，兼容旧作品库与播放状态"
        ])
    ]
    static var latest: ChangelogEntry? { entries.first }
}
