import SwiftUI

/// "+18" marker for adult titles: overlaid on posters and shown next to the title on the detail page.
public struct AdultBadge: View {
    public init() {}

    public var body: some View {
        Text("+18")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, Theme.Spacing.xs)
            .frame(minHeight: 18)
            .background(Theme.accentDeep, in: Capsule())
            .foregroundStyle(.white)
            .accessibilityLabel("Contenido para adultos")
    }
}
