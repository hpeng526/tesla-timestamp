#if canImport(UIKit)
import SwiftUI
import UIKit

/// Off-main-thread thumbnail loader backed by `NSCache` for smooth scrolling through large clip lists.
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()

    private let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 48
        return c
    }()

    func image(for key: String) -> UIImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: UIImage, for key: String) {
        cache.setObject(image, forKey: key as NSString)
    }
}

struct AsyncClipThumbnailView: View {
    let source: MediaSource
    let onTap: () -> Void

    @State private var image: UIImage?
    @State private var appeared = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(TeslaColors.thumbnailPlaceholder)

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 104, height: 64)
                        .clipped()
                        .opacity(appeared ? 1.0 : 0.0)
                        .animation(.easeOut(duration: 0.16), value: appeared)
                } else {
                    Image(systemName: "video.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(TeslaColors.onSurfaceVariant.opacity(0.45))
                }
            }
            .frame(width: 104, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("时间戳预览")
        .task(id: source.key) {
            let cacheKey = "thumb:\(source.key)"
            if let cached = ThumbnailCache.shared.image(for: cacheKey) {
                self.image = cached
                self.appeared = true
                return
            }
            self.image = nil
            self.appeared = false
            if let cgImage = await PreviewComposer.loadThumbnail(source: source, maxWidth: 280) {
                let uiImg = UIImage(cgImage: cgImage)
                ThumbnailCache.shared.insert(uiImg, for: cacheKey)
                guard !Task.isCancelled else { return }
                self.image = uiImg
                self.appeared = true
            }
        }
    }
}
#endif
