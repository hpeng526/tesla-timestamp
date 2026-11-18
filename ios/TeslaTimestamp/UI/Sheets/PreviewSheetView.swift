#if canImport(UIKit)
import SwiftUI

struct PreviewSheetView: View {
    let preview: PreviewState
    let onGenerate: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("时间戳预览")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(TeslaColors.onSurface)

                Spacer()

                Button("关闭", action: onClose)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(TeslaColors.brandRed)
            }

            Image(uiImage: preview.image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(TeslaColors.teslaDark)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(preview.caption)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(TeslaColors.onSurface)

                Text("预览取自片段第 1 秒，合成时会逐帧刷新真实时间")
                    .font(.system(size: 12))
                    .foregroundStyle(TeslaColors.onSurfaceVariant)
            }

            Button {
                Haptics.tap()
                onGenerate()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                    Text("合成")
                        .font(.system(size: 15, weight: .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Capsule().fill(TeslaColors.brandRed))
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
