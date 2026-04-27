# 项目结构

## 推荐打开方式

- Xcode：打开 `PitcherPlant.xcworkspace`
- VSCode：打开仓库根目录，主要查看 `PitcherPlantApp/Sources`、`PitcherPlantApp/Tests`、`PitcherPlantApp/Resources`

## 主目录

```text
PitcherPlantApp/
├── PitcherPlantApp.xcodeproj   # Xcode 入口
├── Package.swift               # SwiftPM 包定义
├── project.yml                 # XcodeGen 配置
├── Resources/                  # App 图标、本地化和资源
├── Sources/PitcherPlantApp/    # App 源码
├── Tests/                      # Swift 测试
└── script/build_and_run.sh     # 构建和运行脚本
```

## 根目录辅助内容

```text
PitcherPlant.xcworkspace/      # 根目录 Xcode 入口
Fixtures/WriteupSamples/       # 样例 WriteUP 数据
LegacyData/LegacyImport/       # 旧版数据导入资料
GeneratedReports/              # 本地生成报告
Docs/                          # 文档
```

日常开发只需要进入 `PitcherPlantApp`。
