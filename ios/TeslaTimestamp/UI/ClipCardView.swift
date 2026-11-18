#if canImport(UIKit)
import SwiftUI

struct ClipCardView: View {
    let group: ClipGroup
    let selectedIds: Set<String>
    let fullySelected: Bool
    let partlySelected: Bool
    let isDisabled: Bool
    let onToggleGroup: (Bool) -> Void
    let onToggleFile: (ClipFile, Bool) -> Void
    let onPreviewClip: (ClipFile) -> Void

    private var hasAnySelected: Bool {
        fullySelected || partlySelected
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                if let firstFile = group.files.first {
                    AsyncClipThumbnailView(source: firstFile.source) {
                        guard !isDisabled else { return }
                        Haptics.tap()
                        onPreviewClip(firstFile)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundStyle(TeslaColors.onSurface)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(group.cardMetadata)
                        .font(.system(size: 12))
                        .foregroundStyle(TeslaColors.onSurfaceVariant)
                        .lineLimit(2)
                }

                Spacer(minLength: 4)

                Button {
                    Haptics.tap()
                    onToggleGroup(!fullySelected)
                } label: {
                    Image(systemName: checkboxIconName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(hasAnySelected ? TeslaColors.brandRed : TeslaColors.onSurfaceVariant.opacity(0.6))
                        .opacity(partlySelected && !fullySelected ? 0.78 : 1.0)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isDisabled)
                .accessibilityLabel("全选该片段")
            }

            // Camera selection chips (supports 4-cam HW3 and 6-cam HW4 + arbitrary camera names)
            WrappingHStack(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(group.files) { file in
                    let isChecked = selectedIds.contains(file.id)
                    let label = TeslaNaming.cameraLabel(file.camera)
                    FilterChipButton(
                        title: label,
                        isSelected: isChecked,
                        isDisabled: isDisabled
                    ) {
                        Haptics.tap()
                        onToggleFile(file, !isChecked)
                    }
                    .opacity(isChecked ? 1.0 : 0.8)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(TeslaColors.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    hasAnySelected ? TeslaColors.brandRed : TeslaColors.outline,
                    lineWidth: hasAnySelected ? 2 : 1
                )
        )
    }

    private var checkboxIconName: String {
        if fullySelected {
            return "checkmark.square.fill"
        } else if partlySelected {
            return "minus.square.fill"
        } else {
            return "square"
        }
    }
}

/// Custom wrapping layout (`Layout` protocol, iOS 16+) for multi-camera chips.
struct WrappingHStack: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        var height: CGFloat = 0
        var width: CGFloat = 0
        for (idx, row) in rows.enumerated() {
            if idx > 0 { height += verticalSpacing }
            height += row.height
            width = max(width, row.width)
        }
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                item.subview.place(
                    at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                    proposal: ProposedViewSize(item.size)
                )
                x += item.size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct RowItem {
        let subview: LayoutSubview
        let size: CGSize
    }

    private struct Row {
        var items: [RowItem] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let neededWidth = current.items.isEmpty ? size.width : (current.width + horizontalSpacing + size.width)
            if !current.items.isEmpty && neededWidth > maxWidth {
                rows.append(current)
                current = Row(items: [RowItem(subview: subview, size: size)], width: size.width, height: size.height)
            } else {
                current.items.append(RowItem(subview: subview, size: size))
                current.width = neededWidth
                current.height = max(current.height, size.height)
            }
        }
        if !current.items.isEmpty {
            rows.append(current)
        }
        return rows
    }
}
#endif
