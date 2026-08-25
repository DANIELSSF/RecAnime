import SwiftUI

/// Floating glass toast for transient errors (one of the few custom glass surfaces).
public struct ErrorBanner: View {
    public let message: String
    public let retry: (@MainActor () -> Void)?

    public init(message: String, retry: (@MainActor () -> Void)? = nil) {
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.secondary)
            Text(message).font(.subheadline).lineLimit(2)
            if let retry {
                Spacer(minLength: 0)
                Button("Reintentar") { retry() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.m)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, Theme.Spacing.l)
    }
}
