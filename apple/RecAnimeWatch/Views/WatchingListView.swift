import RecAnimeUI
import SwiftUI

/// "Viendo" list. Data wiring arrives with the Watch milestone; this is the visual skeleton.
struct WatchingListView: View {
    private let sample: [(title: String, watched: Int, total: Int)] = [
        ("Sousou no Frieren 2nd Season", 7, 24),
        ("Jujutsu Kaisen 3rd Season", 3, 24),
    ]

    var body: some View {
        List(sample, id: \.title) { item in
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                HStack(spacing: 8) {
                    ProgressView(value: Double(item.watched), total: Double(item.total))
                        .tint(Theme.accent)
                    Text("\(item.watched)/\(item.total)")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .navigationTitle("Viendo")
    }
}
