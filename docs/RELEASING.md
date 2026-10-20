# 打包与发版

维护者发布新版本时按顺序执行：升版 → `package-release` → `verify-surface` → **`publish-release` → `verify-published`** → 本机安装。普通源码贡献不需要运行上传流程。

## 版本三处 + 日志

同一版本必须一致：

| 位置 | 作用 |
|------|------|
| `Packaging/VERSION` | 营销版本真源 |
| `Sources/Musepaper/Domain/AppVersion.swift` | 应用内版本号 |
| `Packaging/Info.plist` | 包内 `CFBundleShortVersionString` |
| `CHANGELOG.md` | 人类可读日志 `## x.y.z — YYYY-MM-DD` |
| `Sources/Musepaper/Domain/Changelog.swift` | 设置页「更新日志」 |

```bash
./scripts/check-version-sync.sh
./scripts/bump-version.sh 0.5.1 "要点一|要点二"
```

## 打包产物

```bash
./scripts/package-release.sh
```

产出在 `release/`（gitignore），形如：

```
Musepaper-0.5.0-arm64.dmg / .zip     # Apple Silicon
Musepaper-0.5.0-x64.dmg / .zip       # Intel
Musepaper-latest-arm64.dmg / .zip
Musepaper-latest-x64.dmg / .zip
latest.json                          # architectures: ["arm64","x64"]
```

默认 `./scripts/package-release.sh` **同时打两种芯片**。仅本机预览可用 `ARCHS="arm64" ./scripts/package-release.sh`。

macOS 用户打开对应芯片的 DMG 后请双击 **「安装并打开.command」**，不要直接点 `Musepaper.app`（未公证时 Finder 会误报「已损坏」）。

本地每种架构各保留最近 20 个版本化包（可用 `KEEP=10 ./scripts/package-release.sh` 调整）。

## 上架 OSS

仓库内 `Packaging/oss.json` 指向维护者的公开下载源，不包含密钥。编译或测试不需要 OSS。自行发布时先将 `.env.example` 复制为 `.env.local`，填写自己的密钥与 `MUSEPAPER_OSS_TARGET`、`MUSEPAPER_OSS_ENDPOINT`、`MUSEPAPER_DOWNLOAD_BASE_URL`，或通过环境变量提供。脚本只读取当前项目的凭据，不读取相邻仓库。

自行分发应用还需要修改 `Sources/Musepaper/Domain/UpdateCheck.swift` 的更新清单地址和 `StudioViewModel.swift` 的下载页地址，否则应用仍会检查维护者的更新源。

```bash
./scripts/publish-release.sh            # 双架构 dmg/zip → latest.json → index.html
./scripts/publish-release.sh --dry-run
./scripts/verify-published.sh           # 公网验收
```

公开 URL（前缀以 `oss.json` 的 `downloadBaseUrl` 为准）：

- `…/Musepaper/index.html` — 下载页（按芯片高亮）
- `…/Musepaper/latest.json`
- `…/Musepaper/Musepaper-<ver>-{arm64,x64}.dmg`
- `…/Musepaper/packs/catalog.json` — 壁纸包（`publish-wallpaper-pack`）

顺序：先传齐安装包，再覆盖清单与下载页。

## 终检

```bash
./scripts/verify-surface.sh
./scripts/verify-published.sh
# 不校验本机安装：SKIP_APP=1 ./scripts/verify-surface.sh
```

源码版本、`release/latest.json`、版本化 dmg/zip、OSS 公开面、本机 `/Applications`（可选跳过）必须同版本；不过禁止宣称「已更新」。


## GitHub macOS Release

Run **Actions → Publish macOS apps → Run workflow** on the reviewed commit. The workflow builds natively on Apple Silicon and Intel, verifies the application and both archives, then creates a new `v<version>` tag and GitHub Release with DMG, ZIP and SHA256 checksums. It refuses to overwrite an existing tag. After publication it downloads every installer anonymously and verifies its checksum. This workflow does not publish to OSS or install an app locally. Windows/Linux package targets remain available for local development and are not part of this macOS release workflow.
