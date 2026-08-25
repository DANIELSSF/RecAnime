import SwiftUI

/// Empty / error state with an optional retry button.
public struct EmptyStateView: View {
    public let title: LocalizedStringKey
    public let message: LocalizedStringKey?
    public let systemImage: String
    public let actionTitle: LocalizedStringKey?
    public let action: (@MainActor () -> Void)?

    public init(
        title: LocalizedStringKey,
        message: LocalizedStringKey? = nil,
        systemImage: String,
        actionTitle: LocalizedStringKey? = nil,
        action: (@MainActor () -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle) { action() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
