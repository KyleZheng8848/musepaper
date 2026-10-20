import Foundation

/// 更新检查纯逻辑（不发请求）。对齐 CPET：只发现新版并引导下载，不静默替换。

enum UpdateCheckStatus: String, Equatable, Sendable {
    case updateAvailable = "update-available"
    case upToDate = "up-to-date"
    case notConfigured = "not-configured"
    case error
}

struct UpdateCheckResult: Equatable, Sendable {
    var status: UpdateCheckStatus
    var current: String
    var latest: String?
    var releasesUrl: String?
    var downloadUrl: String?
    var highlights: [String]
    var message: String

    static func notConfigured(current: String) -> UpdateCheckResult {
        UpdateCheckResult(
            status: .notConfigured,
            current: normalizeVersion(current),
            latest: nil,
            releasesUrl: nil,
            downloadUrl: nil,
            highlights: [],
            message: "未配置更新源。默认读取 OSS 上的 latest.json。"
        )
    }
}

struct UpdateManifest: Equatable, Sendable {
    var version: String
    var releasesUrl: String?
    var highlights: [String]
    var assets: [ReleaseAsset]
}

struct ReleaseAsset: Equatable, Sendable {
    var name: String
    var url: String
}

enum UpdateManifestConfig {
    /// 与 `Packaging/oss.json` 的 downloadBaseUrl + latest.json 对齐。
    static let defaultManifestURL = URL(
        string: "https://sometimesgood.oss-cn-hangzhou-zmf.aliyuncs.com/Musepaper/latest.json"
    )!

    static var hostArchTag: String {
        #if arch(arm64)
        "arm64"
        #else
        "x64"
        #endif
    }
}

func normalizeVersion(_ raw: String) -> String {
    var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.lowercased().hasPrefix("v") {
        s = String(s.dropFirst())
    }
    return s
}

/// 语义化版本比较：a > b → 1，a < b → -1，相等 → 0。
func compareVersions(_ a: String, _ b: String) -> Int {
    func split(_ v: String) -> (nums: [Int], pre: String) {
        let normalized = normalizeVersion(v)
        let parts = normalized.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = String(parts.first ?? "")
        let pre = parts.count > 1 ? String(parts[1]) : ""
        let nums = core.split(separator: ".").map { Int($0) ?? 0 }
        return (nums, pre)
    }
    let x = split(a)
    let y = split(b)
    let len = max(x.nums.count, y.nums.count)
    for i in 0..<len {
        let d = (i < x.nums.count ? x.nums[i] : 0) - (i < y.nums.count ? y.nums[i] : 0)
        if d > 0 { return 1 }
        if d < 0 { return -1 }
    }
    if x.pre == y.pre { return 0 }
    if x.pre.isEmpty { return 1 }
    if y.pre.isEmpty { return -1 }
    return x.pre > y.pre ? 1 : -1
}

private func jsonString(_ any: Any?) -> String? {
    if let s = any as? String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
    if let n = any as? NSNumber { return n.stringValue }
    return nil
}

func parseUpdateManifest(_ raw: Any) -> UpdateManifest? {
    guard let obj = raw as? [String: Any] else { return nil }
    let version = normalizeVersion(
        jsonString(obj["version"])
            ?? jsonString(obj["tag_name"])
            ?? jsonString(obj["latest"])
            ?? jsonString(obj["name"])
            ?? ""
    )
    guard let first = version.first, first.isNumber else { return nil }

    var assets: [ReleaseAsset] = []
    if let rawAssets = obj["assets"] as? [[String: Any]] {
        for item in rawAssets {
            guard let name = jsonString(item["name"]),
                  let url = jsonString(item["url"]) ?? jsonString(item["browser_download_url"])
            else { continue }
            assets.append(ReleaseAsset(name: name, url: url))
        }
    }

    // Musepaper publish-release shape: artifacts.{arm64,x64}.{dmg,zip,dmgUrl,...}
    if let artifacts = obj["artifacts"] as? [String: Any] {
        let base: String? = {
            if let page = jsonString(obj["downloadPage"]), let url = URL(string: page) {
                return url.deletingLastPathComponent().absoluteString
            }
            if let latest = jsonString(obj["latestJson"]), let url = URL(string: latest) {
                return url.deletingLastPathComponent().absoluteString
            }
            return nil
        }()

        for (tag, blockAny) in artifacts {
            guard let block = blockAny as? [String: Any] else { continue }
            for key in ["dmg", "zip", "latestDmg", "latestZip"] {
                guard let name = jsonString(block[key]) else { continue }
                let url: String
                if let explicit = jsonString(block[key + "Url"]) {
                    url = explicit
                } else if let base {
                    url = base.hasSuffix("/") ? base + name : base + "/" + name
                } else {
                    continue
                }
                if !assets.contains(where: { $0.url == url }) {
                    assets.append(ReleaseAsset(name: name, url: url))
                }
                // Keep tag in synthetic alias when filename lacks arch (rare).
                if !name.lowercased().contains(tag),
                   !assets.contains(where: { $0.name == "\(tag)-\(name)" })
                {
                    assets.append(ReleaseAsset(name: "\(tag)-\(name)", url: url))
                }
            }
        }
    }

    let releasesUrl = jsonString(obj["releasesUrl"])
        ?? jsonString(obj["downloadPage"])
        ?? jsonString(obj["html_url"])

    let highlights = (obj["highlights"] as? [Any])?.compactMap { jsonString($0) } ?? []
    return UpdateManifest(version: version, releasesUrl: releasesUrl, highlights: highlights, assets: assets)
}

func pickReleaseAsset(assets: [ReleaseAsset], archTag: String) -> ReleaseAsset? {
    let named = assets.filter { !$0.name.isEmpty && !$0.url.isEmpty }
    func match(_ predicates: [(String) -> Bool]) -> ReleaseAsset? {
        named.first { asset in predicates.allSatisfy { $0(asset.name) } }
    }
    let isArm = archTag == "arm64"
    let archPred: (String) -> Bool = { name in
        let lower = name.lowercased()
        if isArm { return lower.contains("arm64") || lower.contains("aarch64") }
        return lower.contains("x64") || lower.contains("x86_64") || lower.contains("intel")
    }
    return match([{ $0.lowercased().hasSuffix(".dmg") }, archPred])
        ?? match([{ $0.lowercased().hasSuffix(".zip") }, archPred])
}

func evaluateUpdate(
    current: String,
    latest: String,
    releasesUrl: String?,
    downloadUrl: String?,
    highlights: [String] = []
) -> UpdateCheckResult {
    let currentN = normalizeVersion(current)
    let latestN = normalizeVersion(latest)
    if latestN.isEmpty {
        return UpdateCheckResult(
            status: .error,
            current: currentN,
            latest: nil,
            releasesUrl: releasesUrl,
            downloadUrl: downloadUrl,
            highlights: highlights,
            message: "没读到线上版本号，稍后再试。"
        )
    }
    if compareVersions(latestN, currentN) > 0 {
        return UpdateCheckResult(
            status: .updateAvailable,
            current: currentN,
            latest: latestN,
            releasesUrl: releasesUrl,
            downloadUrl: downloadUrl,
            highlights: highlights,
            message: "有新版本 \(latestN)（当前 \(currentN)）。"
        )
    }
    return UpdateCheckResult(
        status: .upToDate,
        current: currentN,
        latest: latestN,
        releasesUrl: releasesUrl,
        downloadUrl: nil,
        highlights: highlights,
        message: "已是最新版本 \(currentN)。"
    )
}

func shouldNotifyUpdate(status: UpdateCheckStatus, latest: String?, seenVersion: String?) -> Bool {
    guard status == .updateAvailable else { return false }
    let latestN = normalizeVersion(latest ?? "")
    guard !latestN.isEmpty else { return false }
    let seen = normalizeVersion(seenVersion ?? "")
    if seen.isEmpty { return true }
    return compareVersions(latestN, seen) > 0
}

func shouldShowUpdateBanner(status: UpdateCheckStatus, latest: String?, dismissedVersion: String?) -> Bool {
    guard status == .updateAvailable else { return false }
    let latestN = normalizeVersion(latest ?? "")
    guard !latestN.isEmpty else { return false }
    let dismissed = normalizeVersion(dismissedVersion ?? "")
    if dismissed.isEmpty { return true }
    return latestN != dismissed
}

func preferredUpdateOpenURL(_ result: UpdateCheckResult) -> URL? {
    if let s = result.downloadUrl, let u = URL(string: s) { return u }
    if let s = result.releasesUrl, let u = URL(string: s) { return u }
    return nil
}
