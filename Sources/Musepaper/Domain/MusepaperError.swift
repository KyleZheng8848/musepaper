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
        case .emptyPrompt: L10n.tr("写一句想看到的画面，或点左侧系列 /「新建」。")
        case .invalidDisplay: L10n.tr("没有找到可用的显示器。")
        case .generationFailed(let reason): L10n.tr("生成失败：\(reason)")
        case .missingImage: L10n.tr("图片文件不存在，无法设为壁纸。")
        case .persistenceFailed(let reason): L10n.tr("保存失败：\(reason)")
        case .wallpaperFailed(let reason): L10n.tr("壁纸替换失败：\(reason)")
        case .invalidConfiguration(let reason): L10n.tr("模型配置无效：\(reason)")
        case .missingAPIKey: L10n.tr("没有保存 API Key。请先在模型设置中填写并保存。")
        case .unauthorized: L10n.tr("API Key 无效或无权访问该模型。")
        case .rateLimited(let retry): retry.map { L10n.tr("请求过于频繁，请在 \($0) 后重试。") } ?? L10n.tr("请求过于频繁，请稍后重试。")
        case .paymentRequired: L10n.tr("服务商拒绝计费请求，请检查余额、用量上限或账单状态。")
        case .networkFailed(let reason): L10n.tr("网络请求失败：\(reason)")
        case .invalidResponse(let reason): L10n.tr("服务返回了无法识别的结果：\(reason)")
        }
    }
}
