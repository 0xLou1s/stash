import SwiftUI

/// Pinterest-style columns: each view goes into whichever column is currently shortest.
struct MasonryLayout: Layout {
    var minColumnWidth: CGFloat = 240
    var spacing: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? minColumnWidth * 3 + spacing * 2
        let frames = frames(for: subviews, in: width)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(for: subviews, in: bounds.width)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func frames(for subviews: Subviews, in width: CGFloat) -> [CGRect] {
        let columnCount = max(1, Int((width + spacing) / (minColumnWidth + spacing)))
        let columnWidth = (width - spacing * CGFloat(columnCount - 1)) / CGFloat(columnCount)
        var columnHeights = Array(repeating: CGFloat.zero, count: columnCount)

        return subviews.map { subview in
            let column = columnHeights.indices.min { columnHeights[$0] < columnHeights[$1] }!
            let height = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height
            let frame = CGRect(
                x: CGFloat(column) * (columnWidth + spacing),
                y: columnHeights[column],
                width: columnWidth,
                height: height
            )
            columnHeights[column] += height + spacing
            return frame
        }
    }
}
