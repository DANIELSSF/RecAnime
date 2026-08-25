import SwiftUI

/// Poster artwork with a neutral placeholder; MAL images are https and cached by URLCache.
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
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
            switch phase {
            case let .success(image):
                image.resizable().aspectRatio(contentMode: .fill)
            default:
                Rectangle().fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityHidden(true)
    }
}
