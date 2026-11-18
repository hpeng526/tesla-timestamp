#if canImport(UIKit)
import AVKit
import SwiftUI

struct VideoPlayerSheetView: View {
    let item: PlayerSheetItem
    let onShare: () -> Void
    let onClose: () -> Void

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    @State private var durationSeconds: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                TeslaColors.teslaDark
                if let player {
                    VideoPlayer(player: player)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 250)

            VStack(alignment: .leading, spacing: 10) {
                Text(item.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(TeslaColors.onSurface)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(infoSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(TeslaColors.onSurfaceVariant)

                HStack(spacing: 10) {
                    Button {
                        Haptics.tap()
                        onShare()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                            Text("分享")
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(TeslaColors.onSurface)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(
                            Capsule().strokeBorder(TeslaColors.outline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.tap()
                        onClose()
                    } label: {
                        Text("关闭")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(
                                Capsule().fill(TeslaColors.brandRed)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .background(TeslaColors.surface.ignoresSafeArea())
        .onAppear(perform: startPlayback)
        .onDisappear(perform: stopPlayback)
    }

    private var infoSubtitle: String {
        if let durationSeconds {
            return "时长 \(durationSeconds) 秒 · 循环播放 · 相册 \(PhotoLibraryExporter.albumName)"
        }
        return "相册 · \(PhotoLibraryExporter.albumName)"
    }

    private func startPlayback() {
        let asset = AVURLAsset(url: item.url)
        let templateItem = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer()
        let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: templateItem)
        self.player = queuePlayer
        self.looper = playerLooper
        queuePlayer.play()

        Task {
            if let duration = try? await asset.load(.duration) {
                let sec = CMTimeGetSeconds(duration)
                if sec.isFinite && sec > 0 {
                    self.durationSeconds = max(1, Int(sec.rounded()))
                }
            }
        }
    }

    private func stopPlayback() {
        player?.pause()
        looper?.disableLooping()
        looper = nil
        player = nil
    }
}
#endif
