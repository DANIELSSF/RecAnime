import SwiftUI

/// "★ 8.71" in secondary gray — the palette keeps a single accent, so no yellow stars.
public struct ScoreLabel: View {
    public let score: Double?

    public init(score: Double?) {
        self.score = score
    }

    public var body: some View {
        if let score {
            Label(score.formatted(.number.precision(.fractionLength(2))), systemImage: "star.fill")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .labelStyle(.titleAndIcon)
        }
    }
}
