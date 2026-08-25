import SwiftUI

/// Compact "TV · 24 ep · 2026" line.
public struct MetadataRow: View {
    public let parts: [String]

    public init(_ parts: [String?]) {
        self.parts = parts.compactMap(\.self).filter { !$0.isEmpty }
    }

    public var body: some View {
        Text(parts.joined(separator: " · "))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}
