import Foundation

enum PromptMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case direct = "直接 Prompt"
    case inspiration = "灵感创作"
    var id: String { rawValue }
}

enum PromptTreatment: String, Codable, CaseIterable, Identifiable, Sendable {
    case original = "原样生成"
    case enhanced = "增强 Prompt"
    var id: String { rawValue }
}

enum EmptySpace: String, Codable, CaseIterable, Identifiable, Sendable {
    case none = "不指定"
    case left = "左侧留白"
    case right = "右侧留白"
    case center = "中央留白"
    var id: String { rawValue }
}

struct PromptDraft: Codable, Equatable, Sendable {
    var input = ""
    var negative = "文字、水印、低清晰度、Dock、菜单栏、任务栏、应用图标、窗口、按钮、状态栏、光标、通知、UI 界面、设备边框、桌面截图"
    var mode: PromptMode = .direct
    var treatment: PromptTreatment = .enhanced
    var emptySpace: EmptySpace = .none
    var referenceImagePaths: [String]? = nil
}
