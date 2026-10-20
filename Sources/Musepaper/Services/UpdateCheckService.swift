import Foundation

/// 拉取 OSS `latest.json` 并轮询。失败不抛到 UI 主路径。
@MainActor
final class UpdateCheckService {
    static let shared = UpdateCheckService()

    private let session: URLSession
    private var watchTask: Task<Void, Never>?
    private(set) var lastResult: UpdateCheckResult?

    private let firstDelay: Duration
    private let interval: Duration
    private let retryAfterError: Duration

    init(
        session: URLSession = {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 8
            config.timeoutIntervalForResource = 12
            return URLSession(configuration: config)
        }(),
        firstDelay: Duration = .seconds(8),
        interval: Duration = .seconds(4 * 3600),
        retryAfterError: Duration = .seconds(15 * 60)
    ) {
        self.session = session
        self.firstDelay = firstDelay
        self.interval = interval
        self.retryAfterError = retryAfterError
    }

    func check(
        current: String = AppVersion.marketing,
        manifestURL: URL = UpdateManifestConfig.defaultManifestURL,
        archTag: String = UpdateManifestConfig.hostArchTag
    ) async -> UpdateCheckResult {
        do {
            var request = URLRequest(url: manifestURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("Musepaper/\(AppVersion.marketing)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                let result = UpdateCheckResult(
                    status: .error,
                    current: normalizeVersion(current),
                    latest: nil,
                    releasesUrl: nil,
                    downloadUrl: nil,
                    highlights: [],
                    message: "更新源返回 HTTP \(http.statusCode)。"
                )
                lastResult = result
                return result
            }
            let raw = try JSONSerialization.jsonObject(with: data)
            guard let manifest = parseUpdateManifest(raw) else {
                let result = UpdateCheckResult(
                    status: .error,
                    current: normalizeVersion(current),
                    latest: nil,
                    releasesUrl: nil,
                    downloadUrl: nil,
                    highlights: [],
                    message: "更新清单格式无法解析。"
                )
                lastResult = result
                return result
            }
            let asset = pickReleaseAsset(assets: manifest.assets, archTag: archTag)
            let result = evaluateUpdate(
                current: current,
                latest: manifest.version,
                releasesUrl: manifest.releasesUrl,
                downloadUrl: asset?.url,
                highlights: manifest.highlights
            )
            lastResult = result
            return result
        } catch {
            let result = UpdateCheckResult(
                status: .error,
                current: normalizeVersion(current),
                latest: nil,
                releasesUrl: nil,
                downloadUrl: nil,
                highlights: [],
                message: "检查更新失败：\(error.localizedDescription)"
            )
            lastResult = result
            return result
        }
    }

    /// 启动后延迟首检，之后按间隔轮询；`onResult` 每次检查回调。
    func startWatching(onResult: @escaping (UpdateCheckResult) -> Void) {
        watchTask?.cancel()
        watchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: firstDelay)
            while !Task.isCancelled {
                let result = await self.check()
                onResult(result)
                let wait = result.status == .error ? retryAfterError : interval
                try? await Task.sleep(for: wait)
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }
}
