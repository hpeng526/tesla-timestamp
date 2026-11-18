#if canImport(UIKit)
import SwiftUI

// MARK: - Data Source Card

struct DataSourceCardView: View {
    @ObservedObject var viewModel: MainViewModel
    let onPickFolder: () -> Void
    let onPickFile: () -> Void
    let onPickPath: () -> Void

    private var controlsEnabled: Bool {
        !viewModel.running && !viewModel.scanning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(TeslaColors.brandContainer)
                        .frame(width: 40, height: 40)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(TeslaColors.brandRed)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("数据来源")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(TeslaColors.onSurface)

                    Text(viewModel.scanning
                         ? (viewModel.scanMessage.isEmpty ? "正在扫描 …" : viewModel.scanMessage)
                         : viewModel.sourceLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(TeslaColors.onSurfaceVariant)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 4)

                Button {
                    Haptics.tap()
                    viewModel.rescan()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(TeslaColors.onSurfaceVariant)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!controlsEnabled || !viewModel.hasChosenSource)
                .opacity((controlsEnabled && viewModel.hasChosenSource) ? 1.0 : 0.4)
                .accessibilityLabel("重新扫描")
            }

            Button {
                Haptics.tap()
                onPickFolder()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("添加 U 盘 / 文件夹")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    Capsule()
                        .fill(controlsEnabled ? TeslaColors.brandRed : TeslaColors.brandRed.opacity(0.45))
                )
            }
            .buttonStyle(.plain)
            .disabled(!controlsEnabled)

            HStack(spacing: 8) {
                Button {
                    Haptics.tap()
                    onPickFile()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "film")
                            .font(.system(size: 14, weight: .semibold))
                        Text("单个视频")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(TeslaColors.onSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        Capsule()
                            .strokeBorder(TeslaColors.outline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!controlsEnabled)

                Button {
                    Haptics.tap()
                    onPickPath()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.badge.gearshape")
                            .font(.system(size: 14, weight: .semibold))
                        Text("本地路径")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(TeslaColors.onSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        Capsule()
                            .strokeBorder(TeslaColors.outline, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!controlsEnabled)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TeslaColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TeslaColors.outline, lineWidth: 1)
        )
    }
}

// MARK: - Overlay Style Card

struct OverlayStyleCardView: View {
    @ObservedObject var viewModel: MainViewModel

    private let positions = ["左上", "右上", "左下", "右下"]
    private let sizes = OverlayStyle.sizeLabels

    private var previewEnabled: Bool {
        !viewModel.groups.isEmpty && !viewModel.running && !viewModel.scanning && !viewModel.previewLoading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("时间戳样式")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(TeslaColors.onSurface)

                Spacer()

                Button {
                    Haptics.tap()
                    viewModel.requestPreview()
                } label: {
                    HStack(spacing: 5) {
                        if viewModel.previewLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "eye")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        Text(viewModel.previewLoading ? "正在生成预览 …" : "预览")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundStyle(previewEnabled ? TeslaColors.brandRed : TeslaColors.onSurfaceVariant.opacity(0.5))
                    .frame(minHeight: 36)
                }
                .buttonStyle(.plain)
                .disabled(!previewEnabled)
            }

            // Position toggle group
            HStack(spacing: 8) {
                Text("位置")
                    .font(.system(size: 12))
                    .foregroundStyle(TeslaColors.onSurfaceVariant)
                    .frame(width: 36, alignment: .leading)

                SegmentedPillGroup(
                    items: positions,
                    selectedIndex: viewModel.positionIndex,
                    isDisabled: viewModel.running
                ) { idx in
                    Haptics.tap()
                    viewModel.positionIndex = idx
                }
            }

            // Size toggle group
            HStack(spacing: 8) {
                Text("字号")
                    .font(.system(size: 12))
                    .foregroundStyle(TeslaColors.onSurfaceVariant)
                    .frame(width: 36, alignment: .leading)

                SegmentedPillGroup(
                    items: sizes,
                    selectedIndex: viewModel.sizeIndex,
                    isDisabled: viewModel.running
                ) { idx in
                    Haptics.tap()
                    viewModel.sizeIndex = idx
                }
            }

            // Content filter chips
            HStack(spacing: 8) {
                Text("内容")
                    .font(.system(size: 12))
                    .foregroundStyle(TeslaColors.onSurfaceVariant)
                    .frame(width: 36, alignment: .leading)

                FilterChipButton(
                    title: "日期",
                    isSelected: viewModel.showDate,
                    isDisabled: viewModel.running
                ) {
                    Haptics.tap()
                    viewModel.showDate.toggle()
                }

                FilterChipButton(
                    title: "摄像头 / 地点",
                    isSelected: viewModel.showDetails,
                    isDisabled: viewModel.running
                ) {
                    Haptics.tap()
                    viewModel.showDetails.toggle()
                }

                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TeslaColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TeslaColors.outline, lineWidth: 1)
        )
    }
}

// MARK: - Selection Bar & Empty State

struct SelectionHeaderBarView: View {
    @ObservedObject var viewModel: MainViewModel

    var body: some View {
        HStack {
            Text("共 \(viewModel.groups.count) 个片段 · \(viewModel.totalFileCount) 个视频")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TeslaColors.onSurfaceVariant)

            Spacer()

            Button {
                Haptics.tap()
                viewModel.selectAll(true)
            } label: {
                Text("全选")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(TeslaColors.brandRed)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.running)

            Button {
                Haptics.tap()
                viewModel.selectAll(false)
            } label: {
                Text("清空")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(viewModel.selected.isEmpty ? TeslaColors.onSurfaceVariant.opacity(0.4) : TeslaColors.onSurfaceVariant)
                    .padding(.horizontal, 8)
                    .frame(height: 36)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.selected.isEmpty || viewModel.running)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }
}

struct EmptyClipsCardView: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(TeslaColors.brandContainer)
                    .frame(width: 56, height: 56)
                Image(systemName: "car.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(TeslaColors.brandRed)
            }

            Text("还没有选择视频")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(TeslaColors.onSurface)

            Text("连接 U 盘后选择 TeslaCam 文件夹，应用会自动按片段整理前视 / 后视 / 左右视频，勾选后即可把时间戳烧录进画面。")
                .font(.system(size: 13))
                .foregroundStyle(TeslaColors.onSurfaceVariant)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            VStack(alignment: .leading, spacing: 8) {
                stepRow("1  通过 USB-C / OTG 转接头连接记录仪 U 盘")
                stepRow("2  在系统文件选择器中选中 TeslaCam 文件夹")
                stepRow("3  勾选片段 → 预览 → 合成导出到相册")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(TeslaColors.surfaceVariant)
            )
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(TeslaColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(TeslaColors.outline, lineWidth: 1)
        )
    }

    private func stepRow(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(TeslaColors.onSurface)
    }
}

// MARK: - Reusable Controls

struct SegmentedPillGroup: View {
    let items: [String]
    let selectedIndex: Int
    let isDisabled: Bool
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items.indices, id: \.self) { idx in
                let isSelected = idx == selectedIndex
                Button {
                    onSelect(idx)
                } label: {
                    Text(items[idx])
                        .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        .foregroundStyle(isSelected ? TeslaColors.onBrandContainer : TeslaColors.onSurface)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(
                            isSelected ? TeslaColors.brandContainer : Color.clear
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)

                if idx < items.count - 1 {
                    Rectangle()
                        .fill(TeslaColors.outline)
                        .frame(width: 1, height: 24)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(TeslaColors.outline, lineWidth: 1)
        )
    }
}

struct FilterChipButton: View {
    let title: String
    let isSelected: Bool
    let isDisabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                }
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .bold : .medium))
            }
            .foregroundStyle(isSelected ? TeslaColors.onBrandContainer : TeslaColors.onSurface)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                Capsule()
                    .fill(isSelected ? TeslaColors.brandContainer : TeslaColors.surfaceVariant.opacity(0.6))
            )
            .overlay(
                Capsule()
                    .strokeBorder(isSelected ? TeslaColors.brandRed.opacity(0.5) : TeslaColors.outline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}
#endif
