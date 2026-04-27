# 发布与验收

PitcherPlant 当前支持两种 macOS 分发模式：

- `ad-hoc`：默认模式，使用本地临时签名生成 ZIP、DMG、xcarchive、dSYM 和 SHA-256 校验文件。该模式不需要 Apple Developer 付费账号，也不会执行 Apple 公证。
- `developer-id`：可选模式，需要 Developer ID Application 证书、Team ID、Apple ID app-specific password 等 GitHub Secrets。该模式会执行签名、公证、staple 和 Gatekeeper 校验。

## 本地 ad-hoc 打包

```bash
cd PitcherPlantApp
./script/package_release.sh --distribution ad-hoc
```

成功后产物位于：

```text
PitcherPlantApp/build/export/PitcherPlant.app
PitcherPlantApp/build/dist/PitcherPlant-macOS.zip
PitcherPlantApp/build/dist/PitcherPlant-macOS.dmg
PitcherPlantApp/build/dist/PitcherPlant.xcarchive.zip
PitcherPlantApp/build/dist/PitcherPlant-dSYMs.zip
PitcherPlantApp/build/dist/PitcherPlant-macOS-checksums.txt
PitcherPlantApp/build/dist/release-notes.md
```

脚本会自动完成：

1. `xcodebuild archive`
2. ad-hoc app 导出
3. ZIP、DMG、xcarchive、dSYM 打包
4. `codesign --verify --deep --strict`
5. `hdiutil verify`
6. ZIP 解包检查
7. DMG 挂载检查
8. SHA-256 checksum 生成

ad-hoc 包在其他机器首次打开时可能触发 Gatekeeper 提示。测试人员可以使用 Control-click 打开，或在系统设置的“隐私与安全性”中选择“仍要打开”。本地测试也可移除隔离属性：

```bash
xattr -dr com.apple.quarantine /Applications/PitcherPlant.app
```

## GitHub Actions 发布

推送 `v*` tag 会触发 `.github/workflows/release.yml`，默认走 `macos-26` runner 上可用的最高版本 Xcode 和 `ad-hoc` 分发并创建 GitHub Release：

```bash
git tag v0.1.0-rc.1
git push origin v0.1.0-rc.1
```

也可以手动运行 Release workflow：

- `dry_run=true`：只上传 artifact，不创建 GitHub Release。
- `dry_run=false`：创建 GitHub Release。
- `distribution=ad-hoc`：默认，无需 Apple Developer 账号。
- `distribution=developer-id`：启用 Developer ID 签名和公证。
- `xcode_path`：可选，手动指定 Xcode.app 路径；留空时自动选择 runner 上可用的最高版本 Xcode。

## Developer ID 可选配置

启用 `developer-id` 时，需要配置这些 GitHub Secrets：

```text
APPLE_CERTIFICATE_BASE64
APPLE_CERTIFICATE_PASSWORD
APPLE_SIGNING_IDENTITY
APPLE_TEAM_ID
APPLE_ID
APPLE_APP_SPECIFIC_PASSWORD
KEYCHAIN_PASSWORD        # 可选，未配置时 workflow 使用临时密码
```

该模式额外执行：

```text
notarytool submit --wait
stapler staple
stapler validate
spctl --assess
```

## 发布验收清单

每次发布至少确认：

- CI workflow 通过。
- Release workflow 通过。
- `PitcherPlant-macOS-checksums.txt` 存在且覆盖 ZIP、DMG、xcarchive、dSYM。
- ZIP 解包后包含 `PitcherPlant.app`。
- DMG 可挂载且包含 `PitcherPlant.app`。
- 本机可以启动 App。
- ad-hoc 分发说明随 release notes 一起上传。
