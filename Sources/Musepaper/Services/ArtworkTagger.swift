import Foundation

struct ArtworkTagger: Sendable {
    /// User-owned like tag. Retag must keep it; the tagger must never invent it.
    static let userLikedTag = "喜欢"

    /// Replace machine tags, keep the user's like, then write the new set.
    static func mergeRetag(
        generated: [String],
        existing: [String],
        isFavorite: Bool,
        dropping extra: Set<String> = []
    ) -> [String] {
        let reserved: Set<String> = extra.union([userLikedTag, "磁盘恢复", "磁盘找回"])
        var tags = generated.filter { !reserved.contains($0) }
        if isFavorite || existing.contains(userLikedTag) {
            tags.insert(userLikedTag, at: 0)
        }
        tags = Array(NSOrderedSet(array: tags).compactMap { $0 as? String }.prefix(12))
        if tags.isEmpty { tags = ["横向壁纸"] }
        return tags
    }

    func fallbackTags(prompt: String, task: InspirationChannel?) -> [String] {
        let text = [prompt, task?.name ?? "", task?.essence ?? "", task?.palette ?? ""].joined(separator: "，")
        var tags: [String] = []
        let rules: [(String, [String])] = [
            ("城市", ["城市", "上海", "建筑", "天际线", "街道"]),
            ("自然", ["森林", "山", "海", "湖", "草原", "峡谷", "自然"]),
            ("宇宙", ["宇宙", "星球", "深空", "月球", "银河"]),
            ("雨", ["雨", "潮湿", "水滴"]),
            ("雾", ["雾", "云海", "薄雾"]),
            ("夜景", ["夜", "深夜", "霓虹"]),
            ("晨光", ["黎明", "清晨", "晨雾", "日出"]),
            ("黄昏", ["黄昏", "日落", "暮色"]),
            ("冷色", ["蓝", "青", "冷色"]),
            ("暖色", ["橙", "琥珀", "暖光", "金色"]),
            ("安静", ["安静", "静谧", "克制", "孤独"]),
            ("电影感", ["电影", "cinematic", "景深"]),
            ("极简", ["极简", "留白", "低细节"]),
            ("未来感", ["未来", "科幻", "赛博"])
        ]
        for (tag, needles) in rules where needles.contains(where: { text.localizedCaseInsensitiveContains($0) }) {
            tags.append(tag)
        }
        if let task, task.name != "磁盘恢复" { tags.insert(task.name, at: 0) }
        tags.removeAll { $0 == "磁盘恢复" || $0 == "磁盘找回" }
        if tags.isEmpty { tags = ["AI 创作", "横向壁纸"] }
        if !tags.contains("横向壁纸") { tags.append("横向壁纸") }
        return Array(NSOrderedSet(array: tags).compactMap { $0 as? String }.prefix(10))
    }
}
