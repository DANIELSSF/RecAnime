import SwiftUI

/// Title2 section header with an optional trailing action ("Ver todo").
public struct SectionHeader<Trailing: View>: View {
    public let title: LocalizedStringKey
    private let trailing: Trailing

    public init(_ title: LocalizedStringKey, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.bold())
            Spacer()
            trailing
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, Theme.Spacing.l)
    }
}

public extension SectionHeader where Trailing == EmptyView {
    init(_ title: LocalizedStringKey) {
        self.init(title) { EmptyView() }
    }
}
