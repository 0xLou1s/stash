import SwiftUI

// nonisolated: layouts read it off the main actor.
nonisolated private struct AspectRatioKey: LayoutValueKey {
    static let defaultValue: CGFloat = 1
}

extension View {
    /// Width / height that `JustifiedLayout` uses to size this view.
    func layoutAspectRatio(_ ratio: CGFloat) -> some View {
        layoutValue(key: AspectRatioKey.self, value: ratio)
    }
}

/// Rows of equal height that fill the full width, like Photos or Flickr.
/// Each row is scaled so its items' widths add up exactly to the container.
struct JustifiedLayout: Layout {
    var rowHeight: CGFloat = 220
    var spacing: CGFloat = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 900
        let frames = frames(for: subviews, in: width)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(for: subviews, in: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func frames(for subviews: Subviews, in width: CGFloat) -> [CGRect] {
        // Clamp extreme panoramas and slivers so one image can't wreck a row.
        let ratios = subviews.map { min(max($0[AspectRatioKey.self], 0.5), 3) }
        var frames: [CGRect] = []
        var row: [CGFloat] = []
        var y: CGFloat = 0

        func fittingHeight(_ row: [CGFloat]) -> CGFloat {
            (width - spacing * CGFloat(row.count - 1)) / row.reduce(0, +)
        }

        func placeRow(_ row: [CGFloat], height: CGFloat) {
            var x: CGFloat = 0
            for ratio in row {
                frames.append(CGRect(x: x, y: y, width: ratio * height, height: height))
                x += ratio * height + spacing
            }
            y += height + spacing
        }

        for ratio in ratios {
            let candidate = row + [ratio]
            let candidateHeight = fittingHeight(candidate)
            if candidateHeight > rowHeight {
                row = candidate
                continue
            }

            // The row is full. Close it either with or without this item,
            // whichever lands closer to the target height.
            if !row.isEmpty, abs(fittingHeight(row) - rowHeight) < abs(candidateHeight - rowHeight) {
                placeRow(row, height: fittingHeight(row))
                row = [ratio]
            } else {
                placeRow(candidate, height: candidateHeight)
                row = []
            }
        }

        // Leave the last row at its natural height instead of stretching it.
        if !row.isEmpty {
            placeRow(row, height: min(rowHeight, fittingHeight(row)))
        }
        return frames
    }
}
