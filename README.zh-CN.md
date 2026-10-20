<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/brand/sofunai-logo-dark.svg">
  <img src="assets/brand/sofunai-logo-light.svg" alt="SofunAI 工作室" width="300" height="80">
</picture>

# Musepaper

**由 [SofunAI 工作室](assets/brand/README.md)出品并维护。**

**[GitHub 仓库](https://github.com/KyleZheng8848/musepaper)**

应用菜单中的 **Musepaper → 关于 Musepaper** 与 **设置 → 关于 Musepaper** 均展示工作室标识和开源主页链接。

[English](README.md) | **[简体中文](README.zh-CN.md)**

文档提供英文与简体中文版本。应用界面目前主要使用简体中文。

Musepaper 是一款原生 macOS AI 壁纸系统。用户创建长期运行的“生成任务”，Agent 围绕主题探索或加强 Prompt，图片模型按批次产出候选；每张作品会获得多个 AI 标签，再由智能作品集筛选并交给轮播自动更换桌面。

应用内置离线 Demo Renderer，也已接入 OpenAI Image API 与 OpenAI-compatible Provider。默认真实模型为 `gpt-image-2`，实际可用模型以你的服务商账户为准。API Key 保存在独立本机凭据文件中，不进入普通配置或 Git；文件权限固定为仅当前用户可读写的 `0600`。该文件为明文，请勿分享或提交。

## 功能

- 临时创作 / 长期生成任务双模式
- 任务可选择“主题探索 / 加强原 Prompt / 探索并加强”，分别控制同内核变化与忠实改写
- 每个任务独立配置生成计划与每批候选数
- 原生 macOS Musepaper 图标：深夜画布、纸张波浪与琥珀色生成火花
- Agent / 大模型 API 负责主题拓展、Prompt 加强和作品多标签；文生图 API 只负责图片生成
- 每张作品保留来源任务、生成 Prompt、收藏状态和多个语义标签
- 智能作品集按任务、包含标签、排除标签和收藏状态动态筛选，不复制图片
- 壁纸轮播可选择全部作品、某个任务或智能作品集作为来源，支持随机/最新/最早顺序
- 离线 Demo Provider 与可插拔真实文生图 Provider
- 多模型配置：OpenAI、OpenAI-compatible、自定义 Base URL
- 独立 Prompt Agent：OpenAI Responses、OpenAI-compatible Chat、Anthropic Messages
- Agent 可复用图片 Provider AK，也可使用独立凭据
- GPT Image 2 文生图；参考图片自动切换到 Image Edits API
- 本机 API Key 配置、连接测试和删除；代码不依赖 macOS Keychain
- 批次大小可配置；Provider 一次只返回 1 张时自动补齐，并保留部分成功结果
- 批次内明确选择、历史按批次展示；未选中时禁止应用
- 生成状态机、失败提示和本地历史
- 读取主屏幕尺寸，多屏一键替换
- 覆盖屏幕的满幅应用策略，不用系统填充色补上下/左右边缘
- 替换前记录旧壁纸并支持恢复
- 每日任务使用日期种子扩展天气、时段和视角，锁定主题内核；结果自动进入作品库
- 图片优先的作品画廊、AI 标签筛选、智能作品集与独立轮播页

## 要求

- macOS 14+
- Swift 6 / Xcode 16+

## 运行

最简单的方式是构建标准 macOS 应用包：

克隆仓库并构建：

```bash
git clone https://github.com/KyleZheng8848/musepaper.git
cd musepaper
./scripts/build-app.sh
open dist/Musepaper.app
```

生成后也可以直接在 Finder 中双击 `dist/Musepaper.app`。应用采用本地临时签名；首次打开若被系统拦截，请在 Finder 中右键应用并选择“打开”。

发版形态为版本化 DMG/ZIP + `latest.json` +「安装并打开」，**默认 arm64 + Intel x64**：

```bash
./scripts/check-version-sync.sh
./scripts/package-release.sh
./scripts/verify-surface.sh
# 产物：release/Musepaper-<版本>-arm64|x64.dmg|.zip
# 安装：打开对应芯片的 DMG → 双击「安装并打开.command」
```

升版示例：`./scripts/bump-version.sh 0.6.0 "要点一|要点二"`（替换为本次目标版本）。完整流程见 [docs/RELEASING.md](docs/RELEASING.md)。

本机壁纸包（图 + Prompt + 标签 + 系列）上传 OSS 见 [docs/WALLPAPER_PACKS.md](docs/WALLPAPER_PACKS.md)：

```bash
./scripts/publish-wallpaper-pack.sh --series 孤独宇宙 --limit 50
```

安装了完整 Xcode 时，也可以使用 SwiftPM：

```bash
swift run Musepaper
```

首次编译可能需要数十秒。生成的演示壁纸保存在 `~/Pictures/Musepaper/`，应用状态保存在 `~/Library/Application Support/Musepaper/snapshot.json`。

## 配置真实模型

1. 首次打开时，点击侧栏底部“设置”。
2. 选择默认的“OpenAI · GPT Image 2”，或新增 OpenAI-compatible 配置。
3. OpenAI 默认 Base URL 为 `https://api.openai.com/v1`，模型为 `gpt-image-2`。
4. 填写 API Key，选择尺寸、质量、格式和超时。候选数由本次创作或壁纸系列决定，不依赖图片服务是否支持批量参数。
5. 点击“保存并测试连接”。Musepaper 会先把 AK/SK 写入普通本机配置 `~/Library/Application Support/Musepaper/credentials.json`（权限 `0600`），再验证模型端点；程序不链接或访问 macOS Keychain。也可以只保存配置、稍后测试。
6. 回到“生成任务”，选择临时创作或一个长期任务并填写本次要求。
7. 点击“生成 N 张”；在结果中比较候选。可立即设为壁纸，也可让作品进入作品库供筛选和轮播使用。

创作页会持续显示当前 Provider、模型、输出尺寸、AK 状态和连接验证结果；没有可用密钥时不会误发生成请求。顶部“目标显示器”可切换屏幕，生成结果会自动裁切为该屏幕的实际分辨率。

## 配置 Agent / 大模型 API

1. 打开“设置 → Agent 与大模型 API”，打开启用开关。
2. OpenAI 配置为 Base URL `https://api.openai.com/v1`、协议 `OpenAI Responses`；文本模型请填写服务商账户实际支持的模型 ID。
3. 使用相同 Provider 时可点击“复用图片模型 AK”；也可以单独填写 AK。
4. 兼容服务可选择 `OpenAI-compatible Chat`；Anthropic 服务选择 `Anthropic Messages`。
5. 点击“保存并测试”。此后 Agent 会在生成任务中按所选策略拓展主题或加强 Prompt，并在图片生成后为每张作品生成多个标签。

Musepaper 不会在键入时请求模型。未启用 Agent 或文本服务暂时失败时，内置规则仍能完成 Prompt 变化与基础多标签，不阻塞图片生成。

## 推荐创作流程

1. 在“生成任务”中新建任务，例如“潮湿、安静、有巨大空间感的未来上海”。
2. 选择 Prompt 策略：想保持主题内核并持续出现不同天气、时段和镜头时选“主题探索”；已有精确 Prompt 时选“加强原 Prompt”。
3. 选择每次生成张数；需要长期供图时，开启该任务的每日定时。
4. 生成后到“作品”页按 AI 标签浏览。可组合任务、标签、排除标签与收藏状态，保存为智能作品集。
5. 到“轮播”页新建播放方案，来源选择任务或智能作品集，再设置随机/时间顺序和更换间隔。
6. “立即下一张”可当场验证来源；启用后，Musepaper 运行期间会按间隔循环应用符合条件的作品。

远程自定义 Provider 强制使用 HTTPS；本机 `localhost`/`127.0.0.1` 服务可以使用 HTTP。GPT Image 账户可能需要先完成组织验证，详见 [OpenAI Image generation guide](https://developers.openai.com/api/docs/guides/image-generation)。

## 测试

```bash
swift test
```

也可以绕过 SwiftPM 执行 Provider 仿真（支持 Apple Silicon 和 Intel Mac）：

```bash
./scripts/run-smoke.sh
```

Provider 仿真使用模拟网络，不产生模型费用；验证本机凭据读写与 `0600` 权限、生成/参考图编辑请求、鉴权、Base64、文件写入及屏幕适配。

`./scripts/run-batch-smoke.sh` 还会运行完整 UI 状态流程并调用系统壁纸设置，适合在单独的 macOS 测试账户中手动执行，不包含在默认 CI 中。

如果出现 `Undefined symbols ... PackageDescription.Package`，请检查当前选中的 Command Line Tools 与 Swift 驱动版本是否匹配。安装完整 Xcode 后运行 `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`，再执行测试。

若 `swift test` 提示 `no such module 'XCTest'`，也请安装并选用完整 Xcode；只有 Command Line Tools 时仍可用 `swift build` 编译和运行 Provider 仿真。

## 接入其他文生图服务

兼容 OpenAI Image API 的服务可直接在界面中配置。其他协议则在 `Sources/Musepaper/Providers/` 新建实现 `ImageProvider` 的类型；网络请求应在 Provider 内完成，AK 必须通过 `CredentialStore` 按需读取。Provider 输出本地图片 URL 数组，后续适配、历史和壁纸流程无需变化。

## 安全默认值

生成任务的定时默认关闭；轮播默认关闭。定时生成只把作品加入作品库，不会直接覆盖桌面；只有用户明确启用的轮播会按来源更换壁纸。壁纸设置失败不会清空上一张壁纸路径。AK 文件位于 `~/Library/Application Support/Musepaper/credentials.json`，目录权限为 `0700`、文件权限为 `0600`；它与普通状态文件 `snapshot.json` 分离。

## 网络与数据

- 图片生成和 Prompt Agent 会把本次 Prompt、参考图片或作品图发送到你配置的模型服务商；真实 API 调用可能产生费用。
- 桌面天气功能使用 Open-Meteo 查询天气与城市；自动定位可能调用系统定位服务及太平洋电脑网、GeoJS 的 IP 定位接口。需要控制位置数据时，请检查天气与定位设置。
- 应用会向内置的维护者 OSS 更新源请求 `latest.json`，只提示新版本并引导下载。自行分发时请修改 `UpdateManifestConfig.defaultManifestURL` 以及 `StudioViewModel` 中的下载页地址。
- OSS 发布脚本为可选维护工具，不是编译或离线 Demo 的前置条件。自行发布请使用自己的存储桶和凭据，详见 [发版文档](docs/RELEASING.md)。

## 参与贡献

提交问题和改动前请阅读 [贡献指南](CONTRIBUTING.md)。报告安全问题请阅读 [安全说明](SECURITY.md)，不要公开上传 API Key、个人作品库或未脱敏的日志。修改安装、功能或数据说明时，请同步更新英文与简体中文 README。

## 许可证

版权所有 © 2026 SofunAI 工作室及 Musepaper 贡献者。源码采用 [MIT License](LICENSE)。第三方模型服务、素材、参考图片及生成内容的使用权取决于相应条款与权利人的授权。

### 界面语言

在 **设置 → Language / 语言** 中选择 **跟随系统、简体中文或 English**。切换立即生效，重启后保留选择；不支持的系统语言回退为英语。提示词、已保存的系列名、标签和作品内容保留原文。

执行 `./scripts/run-localization-smoke.sh` 可验证语言选择、回退、动态文案、资源覆盖及内容保留，无需 XCTest。

### 整合版本 0.5.63

本次将 0.5.62 的动效与模型更新，合并进支持中英文选择和 SofunAI 出品标识的版本：新增闭环随机游走、持续缓动、LLaDA/Qwen 提示词与尺寸适配，以及一轮内不重复的持久化洗牌播放。保留已有作品库、语言偏好及 SofunAI 关于入口。

额外验证：`./scripts/run-integration-smoke.sh`、`./scripts/run-localization-smoke.sh`、`python3 scripts/test_gen_download_page.py`。
