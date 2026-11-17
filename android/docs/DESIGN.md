# 设计说明（Tesla 时间戳）

参考 [claude-code-ui-agents](https://github.com/mustafakendiguzel/claude-code-ui-agents) 的移动端设计方法论：
先定设计系统（色彩 / 字号 / 间距 / 圆角），再用组件与微交互落实，最后按无障碍与深色模式校验。
面向 Android（Material 3 组件体系），目标是“苹果级细节 + 特斯拉品牌感”。

## 1. 设计原则

| 原则 | 落地 |
| --- | --- |
| 目的（Purpose） | 每个入口只做一件事：选数据源 → 选片段 → 预览 → 合成 → 播放 |
| 层级（Hierarchy） | 品牌头部 → 数据源卡片 → 样式卡片 → 片段列表 → 固定操作栏，视线自上而下 |
| 上下文（Context） | 选择器按钮始终可见；合成中禁用输入，只保留“取消” |
| 无障碍（A11y） | 48dp 触控热区、对比度 ≥ 4.5:1、所有图标带 contentDescription |
| 性能（Perf） | 缩略图后台加载 + LruCache、列表用 ConcatAdapter、进度更新按 1% 节流 |

## 2. 设计令牌

### 色彩

浅色（values/colors.xml）

| Token | 值 | 用途 |
| --- | --- | --- |
| brand_red | #E82127 | 主色（按钮、选中态、品牌渐变） |
| brand_red_dark | #8E0D11 | 头部渐变终点 |
| bg | #F4F5F7 | 页面背景 |
| surface | #FFFFFF | 卡片/底栏 |
| on_surface | #13161B | 主文本 |
| on_surface_variant | #5B636E | 次要文本 |
| outline | #DCE0E6 | 卡片描边 |
| success | #1F8E3E | 完成态对勾 |

深色（values-night/colors.xml）把 bg 换成 #0D1015、surface #151A21，主色保持 #E82127，
on_brand 改为白色（白字对 #E82127 对比度约 4.6:1，达到 AA）。

### 字号（values/themes.xml）

| 样式 | 大小 / 字重 | 用途 |
| --- | --- | --- |
| Text.Tesla.Display | 24sp / Bold / -1% 字距 | 品牌标题 |
| Text.Tesla.Title | 16sp / Bold | 卡片标题、Sheet 标题 |
| Text.Tesla.Body | 15sp / Regular | 正文 |
| Text.Tesla.Caption | 12sp / Regular / +2dp 行距 | 辅助信息 |
| Text.Tesla.Mono | 16sp / Bold / monospace | 片段起始时间（数字对齐更稳） |

### 间距与圆角

8pt 网格：`space_xs 4 / space_s 8 / space_m 12 / space_l 16 / space_xl 24 / space_2xl 32`（dp）。
圆角：卡片 20dp、片段卡 18dp、按钮 24-27dp（胶囊）、BottomSheet 顶部 28dp。

## 3. 组件

- **品牌头部**：红色渐变 + 深色收尾，承载标题、副标题、U 盘状态胶囊（圆点 + 文本）与说明入口。
- **数据源卡片**：图标 + 标题 + 当前来源；“添加 U 盘 / 文件夹”为主按钮（54dp 高），
  “单个视频 / 本地路径”为次级描边按钮，右上角刷新图标（44dp 热区）。
- **样式卡片**：位置/字号用 `MaterialButtonToggleGroup`（分段控件，44dp 高，单选必选），
  内容用两个 Filter Chip；“预览”为文字按钮，靠右对齐。
- **片段卡片**：104×64 缩略图（圆角 10dp，加载后 160ms 淡入）+ 等宽时间 + 
  “类别 · 数量 · 体积” + 全选复选框 + 每个摄像头一个 Chip（可单独勾选）。
  选中态卡片描边变品牌红、加粗到 2dp。
- **选择条**：列表头部的“共 N 个片段 · M 个视频 / 全选 / 清空”。
- **底部操作栏**：固定在底部的白色圆角卡片，三种状态共用：
  待机（已选摘要 + 主按钮）、合成中（百分比 + 当前文件 + 进度条 + 取消）、完成（对勾 + 已导出数量 + 播放/全部结果）。
- **Bottom Sheet**：预览（大图 + 说明 + 直接合成）、结果（可播放/分享的列表）、播放器（TextureView 循环播放）。

## 4. 微交互

| 交互 | 触发 | 反馈 |
| --- | --- | --- |
| 按钮/芯片点击 | 触摸 | Material ripple + 触觉反馈（VIRTUAL_KEY）+ 即时状态变化 |
| 缩略图加载 | 列表滚动 | 后台解码，完成后 alpha 0→1 淡入 160ms |
| 选中片段 | 复选/芯片 | 卡片描边变色，底部摘要实时更新数量与体积 |
| 合成进度 | 每 1% 变化 | 进度条线性推进，标题“正在合成 x%”，副标题显示当前片段 |
| 结果送达 | 合成完成 | 自动弹出结果 Sheet，底部栏切换为“已导出 N 个视频” |
| 预览 | 点“预览” | Bottom Sheet 从底部滑入，显示与成品完全一致的静态帧 |

不使用会打断任务的动画：列表变更关闭 `supportsChangeAnimations`，避免排序/刷新时闪烁。

## 5. 无障碍

- 所有交互元素 ≥ 44-48dp；芯片自带最小触控高度。
- 图标按钮都有 contentDescription（如“重新扫描”“使用说明”）。
- 主文本与背景对比度：浅色 on_surface #13161B 对 #FFFFFF ≈ 17:1；深色 #ECEFF3 对 #151A21 ≈ 14:1。
- 字号层级只使用 3 种字重（Bold / Medium / Regular），避免信息噪声。
- 深色模式完整配色（含状态栏、底部导航栏），不做纯黑以降低眩光。

## 6. 状态设计

| 状态 | 界面 |
| --- | --- |
| 空 | 车辆图标 + 标题 + 三步说明（连接 U 盘 / 选择目录 / 预览合成） |
| 扫描中 | 来源行显示“正在扫描…”，按钮禁用，进度条 indeterminate |
| 有数据未选 | 选择条显示片段统计，底部提示“勾选片段后开始合成” |
| 已选 | 底部显示“已选 N 个视频 · 约 X MB”与“位置/字号/内容”摘要 |
| 合成中 | 进度条 + 百分比 + 当前文件名 + 取消（禁用一切输入） |
| 完成 | 结果 Sheet + 底部“已导出 N 个视频 / 播放结果 / 全部结果” |
| 失败 | MaterialAlertDialog 说明原因（如路径不可读、编码器不支持） |

## 7. 与桌面脚本的对应关系

| 桌面脚本 | 本应用 |
| --- | --- |
| `find ... -name "20*-*-*_*-*-*"` | `TeslaCamScanner` 递归识别片段目录 |
| `drawtext text='%{pts:localtime:<epoch>}'` | GL 每帧按 `起始时间 + PTS` 生成时间戳纹理 |
| `box=1:boxcolor=black@0.5 fontsize=50` | 50% 黑色底 + 高度 5.5% 的白色粗体 |
| `-c:a copy` | `AudioSampleCopier` 直接拷贝 AAC 压缩帧 |
| `h264_videotoolbox / libx264` | MediaCodec 硬件 H.264 编码 |
| 输出 `*_timestamped.mp4` | 输出到相册 `Movies/TeslaTimestamp`，同名规则 |
