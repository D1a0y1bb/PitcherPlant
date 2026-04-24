# PitcherPlant

PitcherPlant 现在以 macOS App 作为唯一主线维护，用 Swift 原生实现 Writeup 自动化审计、报告库、历史指纹库、白名单和旧数据迁移。

## 主入口

```bash
cd PitcherPlantApp
swift test
swift build
```

Xcode App 构建：

```bash
cd PitcherPlantApp
xcodebuild -project PitcherPlantApp.xcodeproj -scheme PitcherPlantApp -destination 'platform=macOS' build
```

Xcode 测试：

```bash
cd PitcherPlantApp
xcodebuild -project PitcherPlantApp.xcodeproj -scheme PitcherPlantApp -destination 'platform=macOS' test
```

## 旧数据迁移

首次启动 macOS App 时会读取工作区中的旧数据并迁移到 `.pitcherplant-macos/PitcherPlantMac.sqlite`：

- `.pitcherplant-web-state.json`：旧 Web 任务状态与最近配置
- `reports/**/*.html`：旧 HTML 报告
- `PitcherPlant.sqlite`：旧指纹库与白名单

迁移后，macOS App 的报告库、指纹库和白名单视图会直接使用原生数据库。旧 Python Web/CLI 入口已经退出主线维护。
