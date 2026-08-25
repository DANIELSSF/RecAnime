import SwiftUI

/// Capsule badge tinted with the status color (16 % fill + colored text).
public struct StatusBadge: View {
    public let title: LocalizedStringKey
    public let color: Color

    public init(_ title: LocalizedStringKey, color: Color) {
        self.title = title
        self.color = color
    }

    public var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .frame(height: 20)
            .background(color.opacity(0.16), in: Capsule())
            .foregroundStyle(color)
    }
}
