import SwiftUI

/// Lays its children out in rows that wrap when the width runs out, each row centred.
struct AimFlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let rows = rows(of: sizes, maxWidth: proposal.width ?? .infinity)
        let height = rows.map { row in row.map { sizes[$0].height }.max() ?? 0 }.reduce(0, +)
            + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: rows.map { width(of: $0, sizes: sizes) }.max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        var y = bounds.minY
        for row in rows(of: sizes, maxWidth: bounds.width) {
            var x = bounds.minX + (bounds.width - width(of: row, sizes: sizes)) / 2
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            for index in row {
                subviews[index].place(at: CGPoint(x: x, y: y + (rowHeight - sizes[index].height) / 2),
                                      anchor: .topLeading, proposal: ProposedViewSize(sizes[index]))
                x += sizes[index].width + spacing
            }
            y += rowHeight + lineSpacing
        }
    }

    /// Indices of the children in each row.
    private func rows(of sizes: [CGSize], maxWidth: CGFloat) -> [[Int]] {
        var rows: [[Int]] = []
        var current: [Int] = []
        var currentWidth: CGFloat = 0
        for (index, size) in sizes.enumerated() {
            let widthWithChild = current.isEmpty ? size.width : currentWidth + spacing + size.width
            if !current.isEmpty && widthWithChild > maxWidth {
                rows.append(current)
                current = [index]
                currentWidth = size.width
            } else {
                current.append(index)
                currentWidth = widthWithChild
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private func width(of row: [Int], sizes: [CGSize]) -> CGFloat {
        row.map { sizes[$0].width }.reduce(0, +) + spacing * CGFloat(max(row.count - 1, 0))
    }
}
