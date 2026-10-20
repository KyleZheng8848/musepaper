# CHECKLIST: musepaper

> 编码前落盘；完成打 `[x]`。未勾完禁止宣称完成。

## A. 规格与闸门

- [x] PRD.md 含 ≥5 核心功能 + 非目标 + 验收
- [x] 已对照 complexity-bar 写达标策略
- [x] 复用 skill 表含 harsh-optimize-loop
- [x] BUILD_PROMPT.md 已生成并指向本清单

## B. 架构骨架

- [x] 目录分层 ≥4
- [x] 领域模型/类型就位
- [x] 配置与错误类型统一
- [x] 持久化与生成 pipeline 空路径可跑

## C. 功能交付（对应 PRD）

- [x] Prompt 工作台与原样/增强模式
- [x] 灵感频道的创建、编辑、选择与持久化
- [x] 可审阅最终 Prompt 的确定性解析器
- [x] Provider 可插拔生成流水线与状态
- [x] 显示器读取及壁纸尺寸适配
- [x] 预览、一键设置、多屏与回滚
- [x] 本地计划调度与确认安全开关
- [x] 历史记录与收藏
- [x] 多模型配置中心与活动配置切换
- [x] AK 使用独立本机凭据文件（0600），不进入普通配置、日志或 Git
- [x] OpenAI Image API (`gpt-image-2`) 真实生成 Provider
- [x] 自定义 OpenAI-compatible Base URL
- [x] 连接测试、超时、鉴权、限流、余额与响应解析错误
- [x] 生成数量、图片尺寸、质量、格式配置
- [x] 参考图片走 `/images/edits` multipart 请求
- [x] 取消、重试、多候选、低电量/断网跳过与历史限额
- [x] 创作页显示活动模型、AK 与连接状态，缺配置时直达设置
- [x] “保存并测试”原子完成配置校验、本机 AK 保存和连接验证
- [x] 侧栏不再把真实 Provider 误标为 Demo
- [x] 用户可选择目标显示器并看到实际输出分辨率
- [x] 首屏改为“创作指令 + 壁纸画布”双栏，预览无需滚动即可看见
- [x] 模型状态、最终 Prompt 和次要操作降低视觉噪音，生成动作保持唯一主按钮
- [x] 历史页改为作品网格，空状态与有内容状态保持统一作品感
- [x] 设置页使用分组卡片和固定标题区，不再呈现默认开发者 Form 观感
- [x] 去掉硬编码的默认 Prompt；“增强 Prompt”可由配置文本模型真实执行
- [x] 提示词模型独立支持 Responses / Chat Completions / Anthropic Messages
- [x] 提示词模型 AK 可复用当前图片模型凭据并可测试连接
- [x] AI 优化显式触发、可取消/报错、结果进入可编辑最终 Prompt
- [x] 壁纸应用使用覆盖屏幕策略，动态验证不再出现系统填充色边缘
- [x] 壁纸系列支持不可变内核、可变维度、色板、禁用项、参考图与默认候选数
- [x] Prompt Agent 可把一句灵感拆解为可编辑系列蓝图
- [x] 创作页明确展示“设计→优化→生成→选择→应用”状态
- [x] 一次生成 1–4 张形成批次，候选可对比、选择且选择被持久化
- [x] 只能应用明确选中的候选，不再隐式使用 records 第一张
- [x] 定时任务绑定壁纸系列，日期种子生成同内核不同表现的 Prompt
- [x] 定时应用模式消除“需确认 + 自动应用”矛盾开关，默认仅生成待审
- [x] 作品库按生成批次表达候选关系，而不是扁平日志
- [x] Musepaper 原生 AppIcon 已生成 16–1024px 全尺寸资源，写入 `.icns` 并通过应用包读取验证
- [x] 启动只查凭据元数据、不读取 Keychain 秘密；连续两次冷启动无密码弹窗
- [x] 代码完全移除 Keychain 依赖，AK/SK 只使用普通本机配置且不重复弹系统密码
- [x] 生成任务支持主题探索 / Prompt 加强 / 混合策略及任务级每日计划
- [x] 每张作品保存来源任务和多个标签，Agent 不可用时本地标签器降级
- [x] 作品页支持 AI 标签筛选与任务/标签/收藏组合的智能作品集
- [x] 轮播可使用全部作品、单个任务或智能作品集，并支持顺序、间隔和立即切换
- [x] 设置明确分离 Agent / 大模型 API 与文生图 API 的职责

## D. 测试与质量

- [x] 可执行 Smoke 25 项全绿，批次端到端 Smoke 全绿；另有 38 个 XCTest（本机 SwiftPM 清单库错配，未通过 `swift test` 启动）
- [x] README：安装、运行、测试、示例
- [x] C1–C6 数值写入下方“实测”

## E. harsh-optimize-loop（编码必做）

- [x] 对齐四槽位
- [x] P0/P1 建议表（设计杠杆 + 失败类型）
- [x] 按表改代码
- [x] 最小验证（改前伤口 + 改后试跑 + 对照目的）
- [x] 结论写入 `HARSH_LOOP.md`

## 实测

- 源文件数：29 个 Swift 业务源文件
- 约行数：3416 行业务源码
- 测试用例数：40 个 XCTest + 25 个协议/凭据/适配 Smoke 检查 + 1 个完整批次/标签/作品集/轮播 Smoke
- 测试命令与结果：`./scripts/run-smoke.sh` → `SMOKE_OK checks=25 keychain=absent credentials=config-0600 ...`；`./scripts/run-batch-smoke.sh` → `BATCH_FLOW_OK count=4 tags=multiple smart_collection=4 playlist_source=4 selected=3 applied=0 unique_files=4`；Swift 6 严格编译、App 0.3.0 构建、Info.plist、codesign、Prompt Agent HTTP 仿真和真实窗口目视验收均通过；`swift test` 仍被本机 Command Line Tools 的 `PackageDescription` 链接错配阻断
