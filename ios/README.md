# Tesla 时间戳（iOS）

[![iOS CI](https://github.com/hpeng526/tesla-timestamp/actions/workflows/ios.yml/badge.svg)](https://github.com/hpeng526/tesla-timestamp/actions/workflows/ios.yml)

把特斯拉行车记录仪（TeslaCam）U 盘里的视频读出来，**在 iPhone / iPad 上逐帧把时间戳烧录进画面**，再导出到系统相册。

本项目是仓库 Android 应用（[`../android/`](../android/)）与桌面脚本（`add_timestamp.sh` / `add_timestamp.ps1`）的原生 iOS / iPadOS 版本：
纯原生 Apple 媒体框架（`AVFoundation` + `CoreImage` Metal GPU + `VideoToolbox` 硬件编解码），不依赖 ffmpeg、不需要联网。

---

## 功能

- **读取 U 盘 / TeslaCam 目录**：通过 iOS 系统文件选择器（`UIDocumentPickerViewController` + Security-Scoped URL）直接访问 USB-C / OTG U 盘中的 `TeslaCam`（或 `SavedClips` / `SentryClips` / `RecentClips`）目录，自动按分钟片段整理 `front` / `back` / `left_repeater` / `right_repeater` / `left_pillar` / `right_pillar` 视频。
- **解析 event.json**：读取事件时间、城市、经纬度、事件原因（哨兵事件 / 手动保存 / 鸣笛保存 / 碰撞事件…），可作为时间戳第二行烧录进画面。
- **逐帧时间戳 GPU 合成**：时间 = 片段起始时间（取自 `YYYY-MM-DD_HH-MM-SS` 文件名或目录名，按手机本地时区）+ 帧 PTS，秒级刷新，每秒仅在文本变化时重建一次纹理，与桌面脚本和 Android 版一致。
- **WYSIWYG 预览**：合成前用片段第 1 秒画面 + 真实字号比例/位置渲染静态预览图，所见即所得。
- **样式可调**：位置（左上/右上/左下/右下）、字号（小/中/大，基准为画面高度 5.5%）、是否显示日期、是否显示摄像头与地点。
- **应用内循环播放 / 系统分享**：合成结果可直接在应用内循环播放（`AVQueuePlayer` + `AVPlayerLooper`），或通过系统分享面板发送。
- **导出到系统相册**：自动写入系统“照片”应用的 `TeslaTimestamp` 相簿（兼容“仅添加照片”与“完全访问”权限）。
- **批量处理与随时取消**：支持一次勾选多个片段或单独勾选某几个机位，顺序批量合成，支持随时取消并自动清理临时文件。
- **深色模式 / 横竖屏 / iPad 适配 / 无障碍**：完整复刻特斯拉品牌视觉令牌（Brand Red `#E82127`）、触觉反馈（Haptics）与无障碍标签。

## 使用步骤

1. 将特斯拉行车记录仪 U 盘接到 iPhone / iPad（USB-C 机型直插；Lightning 机型使用 Apple Lightning 转 USB 3 相机转换器）。
2. 打开应用，点击 **“添加 U 盘 / 文件夹”**，在系统文件选择器底部“浏览”进入 U 盘，选中 `TeslaCam` 文件夹并点击右上角 **“打开”**。
3. 列表按时间倒序显示片段；点卡片右侧复选框选中整个片段，或点击“前视 / 后视 / 左后 / 右后 / 左柱 / 右柱”芯片单独勾选某个机位。
4. 点击 **“预览”**（或直接点击片段缩略图）确认时间戳的位置、字号与第二行信息。
5. 点击 **“合成 N 个视频”**，底部进度条实时显示百分比，完成后可在结果面板直接 **播放 / 分享**。
6. 成品自动保存在系统相册 `TeslaTimestamp` 相簿中，导出文件名形如 `2024-05-01_13-00-00_front_timestamped.mp4`。

> 也可以点击“单个视频”直接处理某一个 `.mp4`，在“文件”App 中用“共享 → Tesla 时间戳”打开视频，或通过 Finder / 文件共享将素材放入 `我的 iPhone / Tesla 时间戳 / TeslaCam` 后用“本地路径”扫描。

## 技术实现

纯原生 Swift、零第三方依赖，全链路硬件加速：

```
文件（USB OTG Security-Scoped URL / 本地文件）
   │  AVURLAsset + AVAssetReader
   ▼
VideoToolbox 硬件解码（H.264 / HEVC） ──► CVPixelBuffer (Metal 兼容)
                                              │  CoreImage (MTLDevice GPU)：
                                              │  方向矫正 + CoreText/CGContext 时间戳纹理叠加
                                              ▼
                                 AVAssetWriterInput (VideoToolbox H.264 硬件编码)
                                              │
                                              ▼
                       AVAssetWriter MP4 封装（faststart + AAC 音频压缩帧直通拷贝）
                                              │
                                              ▼
                              PHPhotoLibrary → 系统相册 TeslaTimestamp
```

### 目录结构

```
ios/
├── TeslaTimestamp.xcodeproj         Xcode 工程（iOS 16.0+，iPhone & iPad）
├── Package.swift                    Swift Package（供命令行快速运行核心单测）
├── TeslaTimestamp/
│   ├── App/
│   │   ├── TeslaTimestampApp.swift  应用入口与外部视频打开处理（onOpenURL）
│   │   └── Info.plist               相册权限说明、文档类型与文件共享配置
│   ├── Core/
│   │   ├── Data/
│   │   │   ├── TeslaNaming.swift    文件名/目录名时间戳与机位解析
│   │   │   ├── ClipPath.swift       相对路径 → 片段归属（Recent/Saved/Sentry）
│   │   │   ├── ClipModels.swift     片段与机位数据模型
│   │   │   ├── EventJson.swift      event.json 解析与事件原因映射
│   │   │   ├── TeslaCamScanner.swift 目录递归扫描、分组与排序
│   │   │   ├── MediaSource.swift    统一媒体源与 Security-Scoped 访问管理
│   │   │   └── TimeFormats.swift    时间、时长与文件体积格式化
│   │   └── Media/
│   │       ├── OverlayStyle.swift         样式预设与文案拼装
│   │       ├── OverlayBitmapFactory.swift CoreText + CoreGraphics 时间戳位图绘制
│   │       ├── PreviewComposer.swift      合成前静态帧 WYSIWYG 预览与缩略图提取
│   │       ├── TimestampTranscoder.swift  AVAssetReader + Metal CIContext + AVAssetWriter 全流程
│   │       └── TimestampVideoProcessor.swift 生命周期、错误描述与取消清理封装
│   ├── Export/
│   │   └── PhotoLibraryExporter.swift 导出到系统相册 TeslaTimestamp 相簿
│   ├── USB/
│   │   └── UsbVolumeMonitor.swift   外接 U 盘 / LiveFiles 挂载卷状态检测
│   ├── UI/                          SwiftUI 界面、ViewModel、选择器与预览/结果/播放器弹窗
│   └── Resources/Assets.xcassets    应用图标与配色资源
└── TeslaTimestampTests/             单元测试与视频转码测试
```

## 下载与安装

### 方式一：下载未签名 IPA 自签安装（无需 Mac / 无需付费开发者账号）

从仓库 [Releases](https://github.com/hpeng526/tesla-timestamp/releases) 下载 `tesla-timestamp-vX.Y.Z-unsigned.ipa`，使用任一常见工具配合你自己的免费 Apple ID 签名安装即可：

- **[Sideloadly](https://sideloadly.io/)**（Windows / macOS，最简单）：连接手机 → 拖入 `.ipa` → 输入 Apple ID 一键安装（首次需在手机“设置 → 通用 → VPN 与设备管理”中信任开发者，并开启开发者模式）。
- **[AltStore](https://altstore.io/) / [SideStore](https://sidestore.io/)**：支持在手机端同 Wi-Fi / 本地 VPN 自动续签，免去免费证书 7 天过期的手动重签。
- **[LiveContainer](https://github.com/LiveContainer/LiveContainer)**：导入未签名 `.ipa` 直接在容器内运行，不额外占用免费账号的 3 个 App 名额。
- **TrollStore（巨魔）**：已包内附带 ad-hoc `CodeDirectory` 哈希，支持巨魔的设备可直接永久免签安装。

### 方式二：怎么发一个新版本（维护者）

- **本地打标签推送**：`git tag -a v1.0.2 -m "Release v1.0.2" && git push origin v1.0.2`，`Android CI` 与 `iOS CI` 会自动并行构建，把 `.apk` 和 `-unsigned.ipa` 上传到同一个 Release。
- **网页一键发布**：仓库 `Actions` → `Android CI`（同时发双端）或 `iOS CI`（仅构建/补传 iOS IPA）→ **Run workflow** → 填版本号（如 `1.0.2`）即可。

---

## 本地源码构建与运行

环境：macOS + Xcode 15.0+（部署目标 iOS 16.0+）。

### 1. 使用 Xcode 打开（真机 / 模拟器运行）

```bash
open ios/TeslaTimestamp.xcodeproj
```

在 Xcode 中选择 `TeslaTimestamp` Scheme：
- **模拟器调试**：选择任意 iPhone 模拟器，按 `⌘R` 运行。
- **安装到真机**：在 `Signing & Capabilities` 中选择你的 Apple ID / Team（Personal Team 免费账号即可真机签名），连接 iPhone 后按 `⌘R` 安装。

### 2. 命令行构建与测试

```bash
# 编译 iOS 模拟器包（无需签名证书）
xcodebuild \
  -project ios/TeslaTimestamp.xcodeproj \
  -scheme TeslaTimestamp \
  -sdk iphonesimulator \
  CODE_SIGNING_ALLOWED=NO \
  build

# 运行核心逻辑与媒体管线单元测试
swift test --package-path ios
```

## HW3 / HW4（AI4）兼容性

| 场景 | 处理方式 |
| --- | --- |
| **4 路 / 6 路相机** | 自动识别 `front` / `back` / `left_repeater` / `right_repeater` / `left_pillar` / `right_pillar` 及未来新增机位名 |
| **编码格式** | `AVAssetReader` 原生硬件解码 H.264 与 HEVC，统一硬件编码输出 H.264 MP4（`faststart`） |
| **高分辨率与特殊帧率** | 跟随源分辨率（1280×960、1080p、4K）与源帧率（30fps / 36fps），超出编码器上限时自动按比例降级 |
| **旋转视频与音轨** | 自动解析 `preferredTransform` 旋转并交换输出宽高；有 AAC 音轨时无损直通拷贝，无音轨（Tesla 原厂）自动跳过 |
