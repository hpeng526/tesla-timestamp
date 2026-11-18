# tesla-timestamp

[![Android CI](https://github.com/hpeng526/tesla-timestamp/actions/workflows/android.yml/badge.svg)](https://github.com/hpeng526/tesla-timestamp/actions/workflows/android.yml)

给特斯拉行车记录仪（TeslaCam）视频叠加时间戳的小工具集合。

| 目录 | 说明 |
| --- | --- |
| `add_timestamp.sh` | macOS / Linux 桌面脚本（ffmpeg + jq） |
| `add_timestamp.ps1` | Windows PowerShell 脚本（ffmpeg） |
| [`android/`](android/) | **Android 应用**：在手机上读取 U 盘里的 TeslaCam 视频，逐帧烧录时间戳后导出到相册 |
| [`ios/`](ios/) | **iOS 应用**：在 iPhone / iPad 上读取 U 盘里的 TeslaCam 视频，GPU 逐帧烧录时间戳后导出到系统相册 |

## 移动端应用（Android & iOS）

无需 ffmpeg、纯本地硬件加速处理，支持 TeslaCam 的 RecentClips / SavedClips / SentryClips 目录结构，
兼容 HW3 与 HW4（AI4）的 4 路 / 6 路相机素材。

- **Android**：功能、使用步骤与构建方式见 [android/README.md](android/README.md)。
- **iOS**：功能、使用步骤与构建方式见 [ios/README.md](ios/README.md)。

```bash
# Android 构建与安装
cd android
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

```bash
# iOS 打开工程或命令行构建
open ios/TeslaTimestamp.xcodeproj
xcodebuild -project ios/TeslaTimestamp.xcodeproj -scheme TeslaTimestamp -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

## 桌面脚本

```bash
# macOS / Linux：处理指定目录下所有 TeslaCam 片段
./add_timestamp.sh /path/to/TeslaCam
```

```powershell
# Windows
.\add_timestamp.ps1 -Directory "D:\TeslaCam"
```
