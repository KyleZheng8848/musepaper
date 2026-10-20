import Foundation

enum MusepaperError: LocalizedError, Equatable {
    case emptyPrompt
    case invalidDisplay
    case generationFailed(String)
    case missingImage
    case persistenceFailed(String)
    case wallpaperFailed(String)
    case invalidConfiguration(String)
    case missingAPIKey
    case unauthorized
    case rateLimited(retryAfter: String?)
    case paymentRequired
    case networkFailed(String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .emptyPrompt: "写一句想看到的画面，或点左侧系列 /「新建」。"
        case .invalidDisplay: "没有找到可用的显示器。"
        case .generationFailed(let reason): "生成失败：\(reason)"
        case .missingImage: "图片文件不存在，无法设为壁纸。"
        case .persistenceFailed(let reason): "保存失败：\(reason)"
        case .wallpaperFailed(let reason): "壁纸替换失败：\(reason)"
        case .invalidConfiguration(let reason): "模型配置无效：\(reason)"
        case .missingAPIKey: "没有保存 API Key。请先在模型设置中填写并保存。"
        case .unauthorized: "API Key 无效或无权访问该模型。"
        case .rateLimited(let retry): retry.map { "请求过于频繁，请在 \($0) 后重试。" } ?? "请求过于频繁，请稍后重试。"
        case .paymentRequired: "服务商拒绝计费请求，请检查余额、用量上限或账单状态。"
        case .networkFailed(let reason): "网络请求失败：\(reason)"
        case .invalidResponse(let reason): "服务返回了无法识别的结果：\(reason)"
        }
    }
}
