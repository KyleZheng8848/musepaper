<picture>
  <source media="(prefers-color-scheme: dark)" srcset="assets/brand/sofunai-logo-dark.svg">
  <img src="assets/brand/sofunai-logo-light.svg" alt="SofunAI Studio" width="300" height="80">
</picture>

# Musepaper

**Published and maintained by [SofunAI Studio](assets/brand/README.md).**

**[GitHub repository](https://github.com/KyleZheng8848/musepaper)**

The studio logo is also shown in **Musepaper → About Musepaper** (`关于 Musepaper`) and the About section of Settings (`设置`).

**[English](README.md)** | [简体中文](README.zh-CN.md)

Documentation is available in English and Simplified Chinese. The app interface is currently primarily in Simplified Chinese; the setup instructions below include the Chinese control names for reference.

Musepaper is a native macOS AI wallpaper app. Create recurring generation tasks, let a Prompt Agent explore a theme or refine your prompt, and generate batches of images. AI tags and smart collections organize the results, while wallpaper playlists rotate them on your desktop.

The app includes an offline Demo Renderer and supports the OpenAI Image API and compatible providers. The default image model is `gpt-image-2`; available models depend on your provider account. API keys are stored in a separate local credentials file with `0600` permissions, outside regular app settings and Git. This file stores keys in plain text: keep it private.

## Features

- One-off creation and recurring generation tasks
- Three prompt strategies: explore a theme, refine the original prompt, or combine both
- Per-task generation schedules and configurable batch sizes
- Native macOS icon featuring a night canvas, paper waves, and an amber spark
- A separate text-model API for theme exploration, prompt refinement, and artwork tagging; the image API handles image generation
- Artwork records with their source task, generation prompt, favorites, and semantic tags
- Smart collections filtered by task, included or excluded tags, and favorites, without duplicating image files
- Wallpaper playlists sourced from all artwork, a task, or a smart collection, with shuffle, newest-first, and oldest-first ordering
- An offline Demo Provider and pluggable image providers
- Multiple model configurations with OpenAI, OpenAI-compatible services, and custom base URLs
- An independent Prompt Agent supporting OpenAI Responses, OpenAI-compatible Chat, and Anthropic Messages
- Shared or separate API keys for the image provider and Prompt Agent
- GPT Image 2 generation, with reference images automatically routed to the Image Edits API
- Local API key management, connection testing, and deletion, without macOS Keychain dependencies
- Configurable batches, automatic completion when a provider returns one image per request, and preservation of partial results
- Explicit candidate selection and batch history; applying a wallpaper requires a selection
- Generation state tracking, error messages, and local history
- Display resolution detection and wallpaper application across multiple displays
- Full-bleed wallpapers without system fill bands at the edges
- Previous wallpaper tracking and restoration
- Date-seeded variations in weather, time of day, and viewpoint for daily tasks, with generated images added to the library
- An image-focused gallery, AI tag filters, smart collections, and a dedicated playlist page

## Requirements

- macOS 14 or later
- Swift 6 / Xcode 16 or later

## Getting started

Build a standard macOS application bundle:

```bash
git clone https://github.com/KyleZheng8848/musepaper.git
cd musepaper
./scripts/build-app.sh
open dist/Musepaper.app
```

You can also open `dist/Musepaper.app` from Finder. The build uses ad hoc signing. If macOS blocks the first launch, right-click the app in Finder and choose **Open**.

Release packaging produces versioned DMG/ZIP files, `latest.json`, and an installation launcher. **Both Apple Silicon (`arm64`) and Intel (`x64`) are built by default.**

```bash
./scripts/check-version-sync.sh
./scripts/package-release.sh
./scripts/verify-surface.sh
# Output: release/Musepaper-<version>-arm64|x64.dmg|.zip
# Open the DMG for your Mac, then run 安装并打开.command inside it.
```

Example version bump: `./scripts/bump-version.sh 0.6.0 "Highlight one|Highlight two"`. Replace the version and highlights for your release. See the [release guide](docs/RELEASING.md) (Simplified Chinese) for the full process.

Local wallpaper packs include images, prompts, tags, and series metadata. See the [wallpaper pack guide](docs/WALLPAPER_PACKS.md) (Simplified Chinese) for OSS publishing:

```bash
./scripts/publish-wallpaper-pack.sh --series 孤独宇宙 --limit 50
```

Replace `孤独宇宙` with the name of a series in your local library.

With a full Xcode installation, you can also run the app through SwiftPM from the repository root:

```bash
swift run Musepaper
```

The initial build may take a while. Demo wallpapers are saved in `~/Pictures/Musepaper/`. App state is stored in `~/Library/Application Support/Musepaper/snapshot.json`.

## Configure an image model

1. Open Settings (`设置`) at the bottom of the sidebar.
2. Select the default `OpenAI · GPT Image 2` configuration or add an OpenAI-compatible provider.
3. The default OpenAI base URL is `https://api.openai.com/v1`, with model `gpt-image-2`.
4. Enter your API key and choose the output size, quality, format, and timeout. The creation task determines the candidate count independently of the provider's batch support.
5. Click Save and Test Connection (`保存并测试连接`). Musepaper first saves the key to `~/Library/Application Support/Musepaper/credentials.json` with `0600` permissions, then checks the model endpoint. It does not access macOS Keychain. You can also save the configuration and test it later.
6. Return to Generation Tasks (`生成任务`), select one-off creation or a recurring task, and enter your prompt.
7. Click Generate N Images (`生成 N 张`) and compare the candidates. Set a result as your wallpaper or keep it in the library for collections and playlists.

The creation page shows the active provider, model, output size, key status, and connection-test result. Generation requests require an available key. Use Target Display (`目标显示器`) at the top to choose a screen; results are cropped to its actual resolution.

## Configure the Prompt Agent

1. Open Settings → Agent and Model API (`设置 → Agent 与大模型 API`) and enable it.
2. For OpenAI, use base URL `https://api.openai.com/v1` and the `OpenAI Responses` protocol. Enter a text-model ID available to your provider account.
3. To share credentials with the image provider, click Reuse Image Model Key (`复用图片模型 AK`), or enter a separate key.
4. For compatible services, choose `OpenAI-compatible Chat`; for Anthropic, choose `Anthropic Messages`.
5. Click Save and Test (`保存并测试`). The Agent then explores themes or refines prompts according to each task's strategy and adds semantic tags after image generation.

Musepaper does not call models while you type. When the Agent is disabled or the text service fails, built-in rules still provide prompt variation and basic tags so image generation can proceed.

## Suggested workflow

1. Create a generation task, such as “a damp, quiet, futuristic Shanghai with a vast sense of space.”
2. Choose a prompt strategy. Theme Exploration (`主题探索`) varies weather, time, and viewpoint while preserving the theme; Refine Original Prompt (`加强原 Prompt`) is useful for a more precise starting prompt.
3. Set the batch size and enable the task's daily schedule if you want a recurring supply of images.
4. Browse AI tags on the Artwork (`作品`) page. Combine task, tag, exclusion, and favorite filters into a smart collection.
5. Create a plan on the Playlists (`轮播`) page, select a task or smart collection as the source, and set the order and interval.
6. Use Next Now (`立即下一张`) to try the source. Once enabled, the playlist rotates matching artwork while Musepaper is running.

Remote providers require HTTPS. Local services at `localhost` or `127.0.0.1` may use HTTP. GPT Image accounts may require organization verification; see the [OpenAI image generation guide](https://developers.openai.com/api/docs/guides/image-generation).

## Testing

```bash
swift test
```

You can also run the provider smoke checks without SwiftPM on either Apple Silicon or Intel:

```bash
./scripts/run-smoke.sh
```

The provider smoke checks use mocked network responses and do not incur model API charges. They cover local credential storage and `0600` permissions, generation and reference-image edit requests, authentication, Base64 decoding, file output, and display adaptation.

`./scripts/run-batch-smoke.sh` exercises the full UI state flow and calls the system wallpaper setter. Run it manually in a separate macOS test account. It is excluded from the default CI workflow.

If you encounter `Undefined symbols ... PackageDescription.Package`, check that the selected Command Line Tools and Swift driver versions match. After installing full Xcode, select it with `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer` and rerun the tests.

If `swift test` reports `no such module 'XCTest'`, install and select full Xcode. With Command Line Tools alone, you can still compile using `swift build` and run the provider smoke checks.

## Add another image provider

Services compatible with the OpenAI Image API can be configured in the app. For another protocol, implement `ImageProvider` in `Sources/Musepaper/Providers/`. Keep network requests inside the provider and read API keys through `CredentialStore` as needed. Providers return local image URLs, which feed into the existing adaptation, history, and wallpaper pipeline.

## Safe defaults

Generation schedules and wallpaper playlists are off by default. Scheduled generation adds artwork to the library without directly replacing the desktop. Only explicitly enabled playlists change wallpapers on an interval. A failed wallpaper change does not clear the previous wallpaper path.

API keys are stored in `~/Library/Application Support/Musepaper/credentials.json`, with `0700` directory permissions and `0600` file permissions, separately from `snapshot.json`.

## Network and data

- Image generation and the Prompt Agent send the relevant prompts, reference images, or artwork to your configured model provider. Real API calls may incur charges.
- Desktop weather uses Open-Meteo for forecasts and city searches. Automatic location may use macOS Location Services and IP-location endpoints from PConline and GeoJS. Review the weather and location settings to control location data.
- The app requests `latest.json` from the maintainer's built-in OSS update source to notify you of new versions and guide downloads. For your own distribution, change `UpdateManifestConfig.defaultManifestURL` and the download-page URL in `StudioViewModel`.
- OSS publishing scripts are optional maintainer tools. Building the app and using the offline Demo do not require OSS. Use your own bucket and credentials when publishing; see the [release guide](docs/RELEASING.md) (Simplified Chinese).

## Contributing

Read the [contribution guide](CONTRIBUTING.md) (Simplified Chinese) before submitting issues or changes. For security reports, follow the [security policy](SECURITY.md) (Simplified Chinese). Keep API keys, personal artwork libraries, and unredacted logs private. When changing setup, features, or data-handling instructions, update both the English and Simplified Chinese READMEs.

## License

Copyright © 2026 SofunAI Studio and Musepaper contributors. The source code is available under the [MIT License](LICENSE). Rights to third-party model services, assets, reference images, and generated content depend on their respective terms and permissions.

### Interface language

Open **Settings → Language / 语言** and choose **Follow System**, **简体中文**, or **English**. Changes apply immediately and are saved for the next launch. Unsupported system languages fall back to English. Prompts, saved series names, tags, and artwork retain their original content.

Run `./scripts/run-localization-smoke.sh` to verify language selection, fallback, interpolation, catalog coverage, and content preservation without XCTest.

### Integrated release 0.5.63

This release combines the 0.5.62 motion and model updates with Chinese/English selection and SofunAI branding. It adds a closed-loop random wander effect, continuous ambient motion, image-model-specific LLaDA/Qwen prompts and sizes, and persistent shuffle playback without repeats within a cycle. Existing libraries and saved preferences remain compatible.

Additional checks: `./scripts/run-integration-smoke.sh`, `./scripts/run-localization-smoke.sh`, and `python3 scripts/test_gen_download_page.py`.
