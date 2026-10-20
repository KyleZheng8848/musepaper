# 壁纸包导出与 OSS 上传

把本机作品库（壁纸图、Prompt、标签、系列等）打成可移植 pack，并上传到阿里云 OSS。
**永不上传** `credentials.json` / API Key。

## 包结构

```
{packId}/
├── manifest.json          # 系列、作品、tags、prompt、筛选条件
├── artworks/
│   ├── {uuid}-1.wallpaper-1.png
│   └── {uuid}-1.prompt.json
└── references/            # 系列参考图（若有）
```

OSS 位置（见 `Packaging/oss.json`）：

```
oss://sometimesgood/Musepaper/packs/{packId}/...
oss://sometimesgood/Musepaper/packs/catalog.json
```

公网示例：

```
https://sometimesgood.oss-cn-hangzhou-zmf.aliyuncs.com/Musepaper/packs/catalog.json
```

## 密钥

项目根 `.env.local`（已 gitignore）：

```bash
OSS_ACCESS_KEY_ID=...
OSS_ACCESS_KEY_SECRET=...
```

可从 `.env.example` 复制模板。脚本只读取项目根目录的 `.env.local` 和环境变量，不读取相邻项目的凭据。自行发布请填写自己的 `MUSEPAPER_OSS_TARGET` / `MUSEPAPER_OSS_ENDPOINT` / `MUSEPAPER_DOWNLOAD_BASE_URL`；上面的维护者地址仅用于说明结构。

## 导出（只落本地）

```bash
# 某个系列最近 50 张
./scripts/export-wallpaper-pack.py --series 孤独宇宙 --limit 50

# 只要收藏
./scripts/export-wallpaper-pack.py --favorites --name "我的收藏"

# 全库元数据（不含图）
./scripts/export-wallpaper-pack.py --metadata-only --name "全库清单"
```

## 上传 OSS

```bash
# 预演
./scripts/publish-wallpaper-pack.sh --series 孤独宇宙 --limit 20 --dry-run

# 实际上传（按系列）
./scripts/publish-wallpaper-pack.sh --series 孤独宇宙 --limit 100

# 收藏
./scripts/publish-wallpaper-pack.sh --favorites --yes

# 全库（约数十 GB，务必确认）
./scripts/publish-wallpaper-pack.sh --yes
```

已存在且同大小的对象默认跳过（`--no-skip-existing` 可强制重传）。

## 回报字段

上传成功后打印 `manifestUrl` / `catalogUrl`。用浏览器打开 `catalog.json` 可看到已发布 pack 列表。
