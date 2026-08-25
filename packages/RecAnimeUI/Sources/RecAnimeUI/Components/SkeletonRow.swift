import SwiftUI

/// Redacted placeholder card row shown while data loads (respects Reduce Motion).
public struct SkeletonCarousel: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    public init() {}

    public var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.m) {
                ForEach(0 ..< 4, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        RoundedRectangle(cornerRadius: Theme.Radius.poster, style: .continuous).fill(.quaternary).frame(width: 140, height: 210)
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 110, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(.quaternary).frame(width: 70, height: 10)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.l)
        }
        .scrollDisabled(true)
        .opacity(pulse ? 0.55 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .accessibilityLabel("Cargando")
    }
}
