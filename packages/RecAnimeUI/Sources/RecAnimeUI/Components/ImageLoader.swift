import Foundation
import SwiftUI

#if canImport(UIKit)
    import UIKit

    public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
    import AppKit

    public typealias PlatformImage = NSImage
#endif

/// Decoded-image cache in front of URLCache: cells that scroll back into view get their poster
/// synchronously (no flicker, no re-decode). Memory bounded by NSCache.
/// Thread-safe memory cache (NSCache is safe to use from any thread). Opts out of the package's
/// MainActor default isolation so the loader actor can use it.
final nonisolated class ImageMemoryCache: @unchecked Sendable {
    private let cache = NSCache<NSURL, PlatformImage>()

    init() {
        cache.countLimit = 400
        cache.totalCostLimit = 120 * 1024 * 1024
    }

    func object(for url: URL) -> PlatformImage? {
        cache.object(forKey: url as NSURL)
    }

    func set(_ image: PlatformImage, for url: URL, cost: Int) {
        cache.setObject(image, forKey: url as NSURL, cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

public actor ImageLoader {
    public static let shared = ImageLoader(session: .shared)

    private nonisolated let cache = ImageMemoryCache()
    private var inflight: [URL: Task<PlatformImage, Error>] = [:]
    private let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    /// Fast path for views: cached image without suspending.
    public nonisolated func cached(_ url: URL) -> PlatformImage? {
        cache.object(for: url)
    }

    public func image(for url: URL) async throws -> PlatformImage {
        if let hit = cache.object(for: url) {
            return hit
        }
        if let task = inflight[url] {
            return try await task.value
        }
        let task = Task<PlatformImage, Error> { [session] in
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, _) = try await session.data(for: request)
            guard let image = PlatformImage(data: data) else { throw URLError(.cannotDecodeContentData) }
            return image
        }
        inflight[url] = task
        defer { inflight[url] = nil }
        let image = try await task.value
        cache.set(image, for: url, cost: data(cost: image))
        return image
    }

    public func clear() {
        cache.removeAll()
    }

    private nonisolated func data(cost image: PlatformImage) -> Int {
        #if canImport(UIKit)
            Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        #else
            Int(image.size.width * image.size.height * 4)
        #endif
    }
}

/// `AsyncImage` replacement backed by `ImageLoader`: instant for cached URLs, fade-in otherwise.
public struct CachedAsyncImage<Placeholder: View>: View {
    private let url: URL?
    private let placeholder: Placeholder
    @State private var image: PlatformImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(url: URL?, @ViewBuilder placeholder: () -> Placeholder) {
        self.url = url
        self.placeholder = placeholder()
        if let url, let hit = ImageLoader.shared.cached(url) {
            _image = State(initialValue: hit)
        }
    }

    public var body: some View {
        ZStack {
            if let image {
                platformImage(image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(reduceMotion ? .identity : .opacity.animation(.easeOut(duration: 0.2)))
            } else {
                placeholder
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageLoader.shared.cached(url) {
                image = hit; return
            }
            image = nil
            if let loaded = try? await ImageLoader.shared.image(for: url), !Task.isCancelled {
                withAnimation { image = loaded }
            }
        }
    }

    private func platformImage(_ image: PlatformImage) -> Image {
        #if canImport(UIKit)
            Image(uiImage: image)
        #else
            Image(nsImage: image)
        #endif
    }
}
