import SwiftUI

/// Footer for a list or grid whose next page failed: the reason plus a visible retry button.
/// Paging never retries on its own, so this row is the only way back.
public struct InlineRetryRow: View {
    public let message: String
    public let retry: @MainActor () -> Void

    public init(message: String, retry: @escaping @MainActor () -> Void) {
        self.message = message
        self.retry = retry
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.secondary)
            Text(message)
                .font(.footnote)
                .lineLimit(2)
            Spacer(minLength: 0)
            Button("Reintentar") { retry() }
                .buttonStyle(.plain)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(minHeight: 44)
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
    }
}
