import SwiftUI

/// Thin progress bar with the accent → watched gradient plus a "7/24" counter.
public struct ProgressPill: View {
    public let watched: Int
    public let total: Int?

    public init(watched: Int, total: Int?) {
        self.watched = watched
        self.total = total
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Theme.progressGradient)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .frame(height: 4)
            Text(total.map { "\(watched)/\($0)" } ?? "\(watched)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private var fraction: CGFloat {
        guard let total, total > 0 else { return watched > 0 ? 0.6 : 0 }
        return min(CGFloat(watched) / CGFloat(total), 1)
    }
}
