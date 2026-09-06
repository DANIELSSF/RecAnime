import SwiftUI

/// Transient glass capsule: offline notice, failed refresh, developer-mode hint. The optional
/// trailing button keeps a 44 pt touch target, so the toast is a real action, never a tooltip.
public struct ToastView: View {
    public let message: String
    public let actionTitle: String?
    public let action: (@MainActor () -> Void)?

    public init(message: String, actionTitle: String? = nil, action: (@MainActor () -> Void)? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Text(message)
                .font(.footnote)
                .lineLimit(2)
            if let actionTitle, let action {
                Button(actionTitle) { action() }
                    .buttonStyle(.plain)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(minHeight: 44)
            }
        }
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .glassEffect(.regular, in: .capsule)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(message)
    }
}
