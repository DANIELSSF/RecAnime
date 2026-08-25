import SwiftUI

/// Poster artwork with a neutral placeholder; cached and decoded once by `ImageLoader`.
public struct PosterImage: View {
    public let url: URL?
    public let width: CGFloat
    public let height: CGFloat
    public let cornerRadius: CGFloat

    public init(url: URL?, width: CGFloat, height: CGFloat, cornerRadius: CGFloat = Theme.Radius.poster) {
        self.url = url
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        CachedAsyncImage(url: url) {
            Rectangle().fill(.quaternary)
                .overlay {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
