#if canImport(UIKit)
import SwiftUI

struct ResultsSheetView: View {
    let results: [ExportResult]
    let failures: [String]
    let onPlay: (ExportResult) -> Void
    let onShare: (ExportResult) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(TeslaColors.success)

                Text("合成完成")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(TeslaColors.onSurface)

                Spacer()
            }

            Text("已导出 \(results.count) 个视频到系统相册 \(PhotoLibraryExporter.albumName)")
                .font(.system(size: 13))
                .foregroundStyle(TeslaColors.onSurfaceVariant)

            if !failures.isEmpty {
                Text("\(failures.count) 个未完成：\n\(failures.joined(separator: "\n"))")
                    .font(.system(size: 12))
                    .foregroundStyle(TeslaColors.warning)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(TeslaColors.surfaceVariant)
                    )
            }

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(results) { item in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(TeslaColors.onSurface)
                                    .lineLimit(1)

                                Text("\(max(1, item.durationMs / 1000)) 秒 · \(TimeFormats.fileSize(item.sizeBytes))")
                                    .font(.system(size: 12))
                                    .foregroundStyle(TeslaColors.onSurfaceVariant)
                            }

                            Spacer(minLength: 8)

                            Button {
                                Haptics.tap()
                                onPlay(item)
                            } label: {
                                Text("播放")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(TeslaColors.brandRed)
                                    .padding(.horizontal, 12)
                                    .frame(height: 36)
                                    .background(
                                        Capsule().fill(TeslaColors.brandContainer)
                                    )
                            }
                            .buttonStyle(.plain)

                            Button {
                                Haptics.tap()
                                onShare(item)
                            } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(TeslaColors.onSurface)
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle().fill(TeslaColors.surfaceVariant)
                                    )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("分享")
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(TeslaColors.surfaceVariant.opacity(0.65))
                        )
                    }
                }
            }
            .frame(maxHeight: 340)

            Button {
                Haptics.tap()
                onClose()
            } label: {
                Text("关闭")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(TeslaColors.onSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        Capsule().strokeBorder(TeslaColors.outline, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .background(TeslaColors.surface.ignoresSafeArea())
    }
}
#endif
