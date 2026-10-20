import XCTest
@testable import Musepaper

final class UpdateCheckTests: XCTestCase {
    func testCompareVersionsNumeric() {
        XCTAssertEqual(compareVersions("0.5.9", "0.5.10"), -1)
        XCTAssertEqual(compareVersions("0.5.10", "0.5.9"), 1)
        XCTAssertEqual(compareVersions("0.5.25", "0.5.25"), 0)
        XCTAssertEqual(compareVersions("v0.6.0", "0.5.99"), 1)
        XCTAssertEqual(compareVersions("1.0.0-beta", "1.0.0"), -1)
    }

    func testParseMusepaperManifestAndPickArm64() throws {
        let json: [String: Any] = [
            "version": "0.5.26",
            "downloadPage": "https://sometimesgood.oss-cn-hangzhou-zmf.aliyuncs.com/Musepaper/index.html",
            "highlights": ["检查更新", "跨芯片选包"],
            "artifacts": [
                "arm64": [
                    "dmg": "Musepaper-0.5.26-arm64.dmg",
                    "zip": "Musepaper-0.5.26-arm64.zip",
                    "dmgUrl": "https://example.com/Musepaper-0.5.26-arm64.dmg",
                    "zipUrl": "https://example.com/Musepaper-0.5.26-arm64.zip",
                ],
                "x64": [
                    "dmg": "Musepaper-0.5.26-x64.dmg",
                    "dmgUrl": "https://example.com/Musepaper-0.5.26-x64.dmg",
                ],
            ],
        ]
        let manifest = try XCTUnwrap(parseUpdateManifest(json))
        XCTAssertEqual(manifest.version, "0.5.26")
        XCTAssertEqual(manifest.releasesUrl, "https://sometimesgood.oss-cn-hangzhou-zmf.aliyuncs.com/Musepaper/index.html")
        let arm = try XCTUnwrap(pickReleaseAsset(assets: manifest.assets, archTag: "arm64"))
        XCTAssertTrue(arm.name.contains("arm64"))
        XCTAssertTrue(arm.url.contains("arm64.dmg"))
        let intel = try XCTUnwrap(pickReleaseAsset(assets: manifest.assets, archTag: "x64"))
        XCTAssertTrue(intel.url.contains("x64.dmg"))
    }

    func testEvaluateUpdateAvailable() {
        let result = evaluateUpdate(
            current: "0.5.25",
            latest: "0.5.26",
            releasesUrl: "https://example.com/index.html",
            downloadUrl: "https://example.com/a.dmg",
            highlights: ["新功能"]
        )
        XCTAssertEqual(result.status, .updateAvailable)
        XCTAssertEqual(result.latest, "0.5.26")
        XCTAssertTrue(shouldShowUpdateBanner(status: result.status, latest: result.latest, dismissedVersion: nil))
        XCTAssertFalse(shouldShowUpdateBanner(status: result.status, latest: result.latest, dismissedVersion: "0.5.26"))
        XCTAssertTrue(shouldNotifyUpdate(status: result.status, latest: result.latest, seenVersion: "0.5.25"))
        XCTAssertFalse(shouldNotifyUpdate(status: result.status, latest: result.latest, seenVersion: "0.5.26"))
    }

    func testEvaluateUpToDate() {
        let result = evaluateUpdate(
            current: "0.5.26",
            latest: "0.5.26",
            releasesUrl: nil,
            downloadUrl: "https://example.com/a.dmg"
        )
        XCTAssertEqual(result.status, .upToDate)
        XCTAssertNil(result.downloadUrl)
        XCTAssertFalse(shouldShowUpdateBanner(status: result.status, latest: result.latest, dismissedVersion: nil))
    }
}
