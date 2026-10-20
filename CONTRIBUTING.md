# 参与贡献

Musepaper 是 macOS 14+ 原生 SwiftUI / AppKit 应用。欢迎提交可复现的问题、文档改进和功能修复。

## 开发环境

- macOS 14 或更新版本，Apple Silicon 或 Intel。
- Xcode 16+ / Swift 6，使用 `xcode-select -p` 和 `swift --version` 确认工具链。
- 构建不需要模型 API Key、OSS 账户或第三方 Swift 包。

在仓库根目录执行：

```bash
swift test
python3 -m unittest discover -s Tests/Publishing -v
./scripts/run-smoke.sh
./scripts/build-app.sh
```

Provider 仿真使用模拟网络和临时文件，不需要真实服务，也不产生模型费用。`run-batch-smoke.sh` 会调用系统壁纸设置，请在单独的 macOS 测试账户中运行。需要手动体验时打开 `dist/Musepaper.app`，选择离线 Demo。

## 代码结构

`Sources/Musepaper/` 按 App、Domain、Services、Providers、Persistence、Platform、UI 分层；`Sources/Shared/` 保存共享的动态效果代码。单元测试在 `Tests/MusepaperTests/`，端到端仿真在 `Tests/Smoke/`。应用图标和安装包配置在 `Packaging/`。

新增模型协议时实现 `ImageProvider`，通过 `CredentialStore` 读取凭据。保持网络请求可注入、测试不访问真实服务，避免把 UI、服务和持久化堆在同一文件中。

## 提交问题与 Pull Request

问题描述请包含 macOS 版本、芯片、Musepaper 版本、复现步骤及预期结果。API 兼容性问题可附脱敏的请求路径和错误码，请删除鉴权头、密钥、个人 Prompt 和参考图片。

Pull Request 请说明改动解决的问题、验证结果和用户可见的变化。按改动范围运行相关测试；不要提交 `.build/`、`.cache/`、`dist/`、`release/`、作品库、凭据或个人环境配置。功能发版和 OSS 上传由维护者处理，普通贡献不需要存储桶权限。
