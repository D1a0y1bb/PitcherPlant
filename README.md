# PitcherPlant

PitcherPlant 是 macOS 原生 WriteUP 自动化审计 App。当前主线只维护 `PitcherPlantApp`，入口、构建、测试和运行都以 Swift/Xcode 为准。

## 直接打开

用 Xcode 打开这个项目：

```bash
open PitcherPlant.xcworkspace
```

在 Xcode 左上角选择 `PitcherPlantApp` scheme，运行目标选择 `My Mac`，点击 Run。

## 命令运行

```bash
cd PitcherPlantApp
./script/build_and_run.sh
```

验证启动：

```bash
cd PitcherPlantApp
./script/build_and_run.sh --verify
```

## 构建与测试

```bash
cd PitcherPlantApp
xcodegen generate
swift test
xcodebuild -project PitcherPlantApp.xcodeproj -scheme PitcherPlantApp -destination 'platform=macOS' build
xcodebuild -project PitcherPlantApp.xcodeproj -scheme PitcherPlantApp -destination 'platform=macOS' test
```

## 目录说明

- `PitcherPlantApp/`：macOS App 主工程，包含 `Package.swift`、`project.yml`、`PitcherPlantApp.xcodeproj`、源码、资源、测试和运行脚本。
- `Fixtures/WriteupSamples/`：审计样例数据，用于本地调试和测试。
- `LegacyData/LegacyImport/`：旧版数据导入资料，首次启动时可迁移到原生数据库。
- `GeneratedReports/`：App 运行时生成的导出报告目录，由本地运行产生。
- `Docs/`：项目说明、迁移说明和维护文档。

## 数据位置

macOS App 的原生数据库位于：

```text
.pitcherplant-macos/PitcherPlantMac.sqlite
```

App 设置页会显示实际数据库目录，并提供打开数据目录的快捷操作。
