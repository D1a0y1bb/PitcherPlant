# PitcherPlant Agent 工作指南

本文档是给后续 Codex/agent 进入 PitcherPlant 仓库时使用的项目级规则。它不是用户手册，而是工程纪律、历史踩坑和已验证解决方案的集中记录。

## 项目定位

PitcherPlant 是一个本地优先的原生 macOS WriteUP 审计工作台，用于安全竞赛提交包审查、证据聚合、报告复核、指纹库和白名单维护。

关键技术事实：

- 平台目标：macOS 26+。
- 语言与 UI：Swift 6.2、SwiftUI、部分 AppKit interop。
- 持久化：SQLite + GRDB。
- 压缩包处理：ZIPFoundation。
- 更新机制：Sparkle，配合 GitHub release/appcast 相关配置。
- 工程生成：XcodeGen，源配置是 `PitcherPlantApp/project.yml`。
- Xcode 工程：`PitcherPlantApp/PitcherPlantApp.xcodeproj` 是生成物，修改 target/source/package 时必须从 `project.yml` 出发。
- 主 bundle：`com.pitcherplant.desktop`，产品名 `PitcherPlant`。

当前主线已经从早期 Web/Python 控制台迁移到原生 macOS App。后续不要恢复旧 Web/HTML 迁移路径、LegacyData、Legacy 报告标记或旧 Python 入口，除非用户明确要求做兼容恢复。

## 工作区规则

进入本仓库后，先确认当前任务属于哪个层面：

- UI/布局：先读最近的页面容器、shared surface 和窗口根视图，不要凭截图猜。
- 数据/审计：先读 `Core/`、`Models/`、`Persistence/` 中对应管线，不要绕开现有模型。
- 发布/更新：先读 `project.yml`、`Resources/Info.plist`、release 脚本和 Sparkle 配置，不要只改 UI。
- 本地化：所有用户可见文案必须走 `LocalizationStrings` 或 `.xcstrings` 的既有机制。
- 工程文件：需要新增 Swift 源文件时，修改 `project.yml` 后再运行 XcodeGen；不要手写维护 `project.pbxproj`。

协作纪律：

- 不要还原用户或其他线程的未提交改动，除非用户明确要求。
- 修改前先识别必须触碰的文件，避免跨层大面积重写。
- 不要为了一个视觉问题重写窗口架构，先找项目里已经生效的页面。
- 不要在没有实机依据时宣称“macOS 做不到”，本项目多次问题都是容器结构不对。
- 提交前必须看真实 diff，提交信息要覆盖实际变动，不要只写当前聊天里提到的单点问题。

## 构建与验证

常用命令从仓库根目录执行：

```bash
cd /Users/d1a0y1bb/Documents/01_projects/PitcherPlant
```

检查补丁格式：

```bash
git diff --check
```

生成 Xcode 工程：

```bash
xcodegen generate --spec PitcherPlantApp/project.yml
```

Debug 构建：

```bash
xcodebuild -project PitcherPlantApp/PitcherPlantApp.xcodeproj -scheme PitcherPlantApp -configuration Debug -destination 'platform=macOS' build
```

单元测试：

```bash
swift test --package-path PitcherPlantApp
xcodebuild -project PitcherPlantApp/PitcherPlantApp.xcodeproj -scheme PitcherPlantApp -destination 'platform=macOS' test
```

构建并启动验证：

```bash
./PitcherPlantApp/script/build_and_run.sh --verify
```

Release 构建：

```bash
xcodebuild -project PitcherPlantApp/PitcherPlantApp.xcodeproj -scheme PitcherPlantApp -destination 'platform=macOS' -configuration Release build
```

验证原则：

- 只改文档时，至少运行 `git diff --check`。
- 改 Swift 源码时，至少运行 Debug `xcodebuild ... build`。
- 改工程 source list、package、resource、Info.plist 时，先运行 `xcodegen generate --spec PitcherPlantApp/project.yml`。
- 改审计核心、数据库、导入导出、并发取消、缓存和性能路径时，运行 SwiftPM 和 Xcode 测试。
- 改窗口、菜单、更新检查、Sparkle、发布产物时，额外运行 `./PitcherPlantApp/script/build_and_run.sh --verify` 并实机观察。

注意：`./PitcherPlantApp/script/build_and_run.sh --verify` 会启动一个真实 `PitcherPlant` 进程。后续重复验证前要考虑已有进程状态。

## UI 与 macOS 原生体验规则

本项目历史上多次在自绘复杂视觉和回归系统原生之间返工。默认规则是：优先使用 macOS/SwiftUI 原生机制，只在系统 API 无法表达产品目标时引入最小 AppKit bridge。

必须遵守：

- 不要默认自绘 toolbar、标题栏、系统模糊、窗口背景或 sidebar 材质。
- 不要给 `NavigationSplitView` 根层随意铺固定白色、黑色或 `windowBackgroundColor`，避免破坏系统材质。
- 不要额外画 Inspector leading separator；优先保留 `HSplitView` 原生分隔线，避免两条竖线叠加变黑。
- 不要对 sidebar、Inspector、detail scroll view 随意叠加 `overlay`、`mask`、`gradient` 来假装系统效果。
- 侧边栏保持轻量 source-list 体验，图标、标题、分组和选中态应稳定一致。
- 设置页保持原生偏好设置方向，避免复杂自绘控件、过重卡片、失衡间距和无法适配深色模式的底色。
- 报告中心、证据详情、代码 diff、图片预览等大内容区域必须考虑大规模数据和横纵向滚动。

已踩过的 UI 坑：

- 自绘 Liquid Glass 胶囊 toolbar 维护成本高，容易导致遮挡、错位、窗口缩放问题，主线后来回归 macOS 官方窗口设计。
- 设置页经历过深色外观、路径布局、搜索、控件对齐、详情栏隐藏、圆角控件、卡片样式多轮返工，后续改动应小步保持原生偏好设置结构。
- 右侧 Inspector 曾出现额外分隔线、顶部 titlebar 遮挡、背景偏黑、空态位置偏高、宽度缩放问题，改 Inspector 先找已有 `ReportInspectorScrollView`、panel surface 和 split width 策略。
- glassEffect 曾出现渲染残影，避免在滚动大列表或复杂背景上盲目叠太多玻璃层。

## Scroll-edge 标题栏模糊经验

这是本仓库当前最重要的 UI 经验之一。

最终证明有效的路径：

```text
NewAuditView -> NativePage -> AppPageShell
```

`AppPageShell` 的关键行为：

```swift
ScrollView {
    VStack(alignment: .leading, spacing: spacing) {
        content
    }
    .padding(.horizontal, AppLayout.pagePadding)
    .padding(.top, AppLayout.titlebarScrollContentTopPadding)
    .padding(.bottom, 22)
    .frame(maxWidth: .infinity, alignment: .topLeading)
}
.ignoresSafeArea(.container, edges: .top)
```

结论：

- 系统 scroll-edge 模糊能力是存在的。
- 新建审计页面一开始就正确，是因为它使用 `NativePage -> AppPageShell`。
- 滚动边缘测试页改成 `AppPageShell` 后立即生效，证明窗口配置不是根因。
- 设置页之前失败，是因为它保留自定义 `ScrollView + padding + safeAreaBar + scrollEdgeEffectStyle/overlay`，系统没有把它当成同一类主滚动内容。
- 设置页嵌入主窗口时改成 `AppPageShell(spacing: 28) { settingsContent }` 后生效。

后续规则：

- 需要标题栏自然吞入/模糊的主内容页，优先复用 `NativePage` 或 `AppPageShell`。
- 顶部空间使用 `AppLayout.titlebarScrollContentTopPadding` 作为内容 padding。
- 主滚动容器对 top 使用 `.ignoresSafeArea(.container, edges: .top)`。
- 不用 `safeAreaBar` 伪造标题栏区域。
- 不用 `overlay`、`mask`、`gradient`、自绘 material 来模拟系统 blur。
- 不把 `.scrollEdgeEffectStyle(.soft, for: .top)` 当作万能修复；先确认页面是否走对主滚动容器。
- 不轻易修改 `NativeToolbarSupport.swift` 或窗口 chrome；先对比已经有效的页面。

## 历史踩坑归纳

项目演进可以按以下阶段理解：

- 早期阶段：从模块化、Web 审计控制台、历史任务、报告入口逐步扩展。
- 原生迁移：新增 macOS 客户端主干，后来主线迁移到 macOS App 并移除 Python 入口。
- 原生报告中心：持续补齐证据视图、总览关联、图片双栏、搜索筛选、桌面命令联动。
- 设置页打磨：围绕原生偏好设置布局、详情栏隐藏、控件层级、深色模式、路径交互和搜索对齐反复修复。
- macOS 26/Liquid Glass：提升最低系统版本，广泛采用新 API，同时删除旧 Legacy/Web 迁移路径。
- 原生 UI 回归：多轮提交移除自绘控件外观、自定义背景、状态色和最后的外观桥接背景。
- Inspector 与 split view：修复背景、分隔线、顶部遮挡、空态位置、宽度策略和滚动表现。
- 悬浮 toolbar 尝试：一度实现自绘 Liquid Glass 胶囊、悬停、融合、展开、分裂动画，后来因复杂和难维护回归官方窗口设计。
- 发布链路：修正 GitHub Actions Swift 工具链、macOS 26 runner、Xcode 版本、ad-hoc 产物、About 版本显示、release tag 注入和发布校验路径。
- 大规模稳定性：增强大规模工作区审计、报告渲染、指纹库加载、图片缓存、代码 diff 缓存、图谱渲染上限和取消流程。
- 更新检查：新增 About、GitHub update checker、Sparkle 相关逻辑，更新 UI 应优先走原生/Sparkle 风格。
- scroll-edge 收口：确认主内容区自然标题栏模糊的稳定实现是复用 `AppPageShell`，不是自绘效果。

发布和更新相关经验：

- `PP_RELEASE_TAG`、`MARKETING_VERSION`、About 显示、Sparkle feed、GitHub release tag 要一起考虑。
- 检查更新 UI 不要自建大 SwiftUI 弹窗；优先使用 macOS/Sparkle 原生窗口或 alert 风格。
- Release 构建、ad-hoc 公开产物、runner/Xcode 版本曾多次出问题，发布改动必须跑完整验证。

性能和稳定性经验：

- 大规模报告和指纹库不能一次性全量加载。
- 图片、代码 diff、图谱和报告列表必须使用缓存、分页、上限或懒加载策略。
- 审计取消必须真实取消后台 `AuditRunner` 任务和子进程，不能只改变按钮视觉状态。
- Office 解析要考虑解压路径、内存上限和临时文件过滤。
- 数据库失败后不能悄悄进入临时库继续工作而不提示风险。

## 本地化与菜单

本项目支持中英文界面。新增用户可见文案必须同步中文和英文。

规则：

- Sidebar、菜单、toolbar、settings、alert、update、report 文案都必须本地化。
- 不要在 SwiftUI view 里硬编码中文作为最终 UI 文案。
- 菜单栏本地化曾经漏掉 `Tasks`、`View`、`Review`、`Reports` 等项，改 commands 或系统菜单后要切换语言实机看。
- Accessibility label、help、button title 应和本地化策略一致。

## 提交与 PR 规则

提交前先看真实工作区：

```bash
git status --short
git diff --stat
git diff --check
```

提交信息规则：

- 覆盖真实 diff，而不是只覆盖当前对话里的最后一个问题。
- 如果变动跨 UI、工程文件、本地化和验证页，要在正文中分组说明。
- 不要把无关未提交改动悄悄纳入提交；如果发现不属于当前任务的改动，先向用户说明。
- 英文提交建议用 Conventional Commit 风格，例如 `fix:`、`feat:`、`docs:`、`chore:`。

常见提交信息示例：

```text
fix: align scroll-edge blur behavior across main content pages
docs: add project agent guidance
fix: localize macOS command menus
perf: improve large report and fingerprint loading
chore: regenerate Xcode project
```

## 新增页面或功能时的默认路径

新增主窗口内容页：

- 在 `MainSidebarItem` 增加 case、标题 key、图标和是否显示 Inspector 的策略。
- 在 sidebar view 增加入口。
- 在 `MainWindowView` detail routing 增加页面。
- 主内容滚动页默认用 `NativePage` 或 `AppPageShell`。
- 用户可见文案同步中英文。

新增 Swift 源文件：

- 修改 `PitcherPlantApp/project.yml` 或确认 source glob 已覆盖。
- 运行 `xcodegen generate --spec PitcherPlantApp/project.yml`。
- 运行 Debug build。

新增设置项：

- 找现有 settings row 组件复用，不要新造一套控件风格。
- 保持设置页分组、圆角背景板、行分隔线和控件列宽一致。
- 同步持久化模型、默认值、本地化和 UI。
- 检查独立 Settings scene 与主窗口嵌入设置页两种 presentation。

新增审计或报告能力：

- 从 `AuditConfiguration`、runner、analyzer、assembler、database、exporter 的数据流补齐。
- 考虑取消、错误展示、分页、大文件、重复导入和缓存。
- 增加或更新测试，尤其是解析、持久化、导出和大规模场景。

## 禁止事项

- 不要恢复旧 Python/Web 主线。
- 不要绕过 XcodeGen 直接长期维护 `project.pbxproj`。
- 不要用自绘遮罩模拟系统标题栏 blur。
- 不要额外画 Inspector 分隔线。
- 不要用固定浅色/深色背景破坏系统材质。
- 不要在用户未要求时运行 destructive git 命令。
- 不要无验证地声称发布、更新、签名或 Sparkle 已经可用。
- 不要只为视觉问题大范围重构数据层或 app state。

## 当前已验证的 scroll-edge 方案摘要

如果未来 agent 只记一条：PitcherPlant 的主内容区标题栏自然模糊，不靠自绘，不靠 `safeAreaBar`，不靠单独调 `scrollEdgeEffectStyle`。先找已经成功的 `NewAuditView`，复用 `NativePage -> AppPageShell` 的滚动容器结构。设置页和滚动边缘测试页的问题都是通过对齐这条路径解决的。
