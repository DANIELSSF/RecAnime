import SwiftUI
import Testing
@testable import RecAnimeUI

@Suite("Theme tokens")
struct ThemeTests {
    @Test("status colors map every library status")
    @MainActor func statusMapping() {
        #expect(Theme.status("watching") == Theme.statusWatching)
        #expect(Theme.status("watched") == Theme.statusWatched)
        #expect(Theme.status("pending") == Theme.statusPending)
        #expect(Theme.status("unknown") == Theme.statusPending)
    }
}
