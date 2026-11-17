# tesla-timestamp

给特斯拉行车记录仪（TeslaCam）视频叠加时间戳的小工具集合。

| 目录 | 说明 |
| --- | --- |
| `add_timestamp.sh` | macOS / Linux 桌面脚本（ffmpeg + jq） |
| `add_timestamp.ps1` | Windows PowerShell 脚本（ffmpeg） |
| [`android/`](android/) | **Android 应用**：在手机上读取 U 盘里的 TeslaCam 视频，逐帧烧录时间戳后导出到相册 |

## Android 应用

无需 ffmpeg、纯本地 GPU 处理，支持 TeslaCam 的 RecentClips / SavedClips / SentryClips 目录结构，
兼容 HW3 与 HW4（AI4）的 4 路 / 6 路相机素材。

功能、使用步骤、技术实现与验证情况见 [android/README.md](android/README.md)。

```bash
cd android
./gradlew :app:assembleDebug
adb install -r app/build/outputs/apk/debug/app-debug.apk
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
