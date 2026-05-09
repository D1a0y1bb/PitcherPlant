# 发布与验收

PitcherPlant 当前支持两种 macOS 分发模式：

- `ad-hoc`：默认模式，使用本地临时签名生成 ZIP、DMG、xcarchive、dSYM 和 SHA-256 校验文件。该模式不需要 Apple Developer 付费账号，也不会执行 Apple 公证。
- `developer-id`：可选模式，需要 Developer ID Application 证书、Team ID、Apple ID app-specific password 等 GitHub Secrets。该模式会执行签名、公证、staple 和 Gatekeeper 校验。

## 本地 ad-hoc 打包

```bash
cd PitcherPlantApp
./script/package_release.sh --distribution ad-hoc
```

当前短期发布策略是不走 Apple Developer 公证：发布包可以继续是 ad-hoc signed、not notarized，但 Sparkle 更新必须使用 EdDSA 签名。GitHub Release workflow 需要配置 `SPARKLE_ED_PRIVATE_KEY` secret；公钥写在 App 的 `SUPublicEDKey` 里，私钥不得提交到仓库。

注意：已经发布且未内置 `SUPublicEDKey` 的版本无法安全验证后续 ad-hoc Sparkle 更新。第一次加入 Sparkle 公钥的版本需要用户手动下载安装；从该版本之后，后续版本才能通过 Sparkle 完整验证并安装。

本地脚本也会生成 Sparkle appcast，因此需要通过环境变量提供 `SPARKLE_ED_PRIVATE_KEY`。如果是在本地制作真实带 tag 的发布包，还要提供对应 release notes：

```bash
cd PitcherPlantApp
RELEASE_TAG=v0.1.8-beta REQUIRE_RELEASE_NOTES=true ./script/package_release.sh --distribution ad-hoc
```

`REQUIRE_RELEASE_NOTES=true` 时，`PitcherPlantApp/ReleaseNotes/<tag>.md` 不存在会直接失败。

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

推送 `v*` tag 会触发 `.github/workflows/release.yml`，默认走 `macos-26` runner 上可用的最高版本 Xcode。workflow 会先检查签名 secrets：资料齐全时使用 `developer-id` 分发并执行公证；资料不全时退到 `ad-hoc` 分发，仍会创建 GitHub Release，但产物没有 Apple 公证。

```bash
git tag v0.1.0-rc.1
git push origin v0.1.0-rc.1
```

真实发布只接受这些 tag：

- 正式版：`vX.Y.Z`
- beta：`vX.Y.Z-beta`
- RC：`vX.Y.Z-rc.N`

真实发布必须存在 `PitcherPlantApp/ReleaseNotes/<tag>.md`。缺少该文件时，workflow 会在发布前检查失败，不会上传 GitHub Release。

也可以手动运行 Release workflow：

- `dry_run=true`：只上传 artifact，不创建 GitHub Release。
- `dry_run=false`：创建 GitHub Release；会要求对应 `ReleaseNotes/<tag>.md` 存在。
- `distribution=ad-hoc`：无需 Apple Developer 账号，产物 ad-hoc signed、not notarized。
- `distribution=developer-id`：启用 Developer ID 签名和公证。
- `xcode_path`：可选，手动指定 Xcode.app 路径；留空时自动选择 runner 上可用的最高版本 Xcode。

正式版会作为 GitHub Latest 发布并使用 stable appcast。beta 和 RC 会以 prerelease 发布，`--latest=false`，客户端和静默检查都使用固定 `appcast-beta` 地址。

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
- `PitcherPlantApp/ReleaseNotes/<tag>.md` 已存在并被打进 `release-notes.md`。
- `PitcherPlant-macOS-checksums.txt` 存在且覆盖 ZIP、DMG、xcarchive、dSYM。
- ZIP 解包后包含 `PitcherPlant.app`。
- DMG 可挂载且包含 `PitcherPlant.app`。
- 本机可以启动 App。
- ad-hoc 分发说明随 release notes 一起上传。
