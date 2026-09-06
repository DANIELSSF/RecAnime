import SwiftUI

/// Vertical poster card for carousels and grids (140×210 by default, scaled with Dynamic Type).
public struct PosterCard: View {
    public let title: String
    public let subtitle: String?
    public let imageURL: URL?
    public let progress: Double?
    public let isAdult: Bool
    @ScaledMetric(relativeTo: .subheadline) private var width: CGFloat = 140

    public init(
        title: String,
        subtitle: String? = nil,
        imageURL: URL?,
        progress: Double? = nil,
        isAdult: Bool = false
    ) {
        self.title = title
        self.subtitle = subtitle
        self.imageURL = imageURL
        self.progress = progress
        self.isAdult = isAdult
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            PosterImage(url: imageURL, width: width, height: width * 1.5)
                .overlay(alignment: .topLeading) {
                    if isAdult {
                        AdultBadge().padding(Theme.Spacing.s)
                    }
                }
            if let progress {
                ProgressView(value: progress)
                    .tint(Theme.accent)
                    .frame(width: width)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .frame(width: width, alignment: .leading)
            if let subtitle {
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: width, alignment: .leading)
            }
        }
        .frame(width: width)
    }
}
