import RecAnimeUI
import SwiftUI
import Testing

/// Locks the public surface the app targets build against: defaults and optional arguments.
@Suite("Components")
@MainActor
struct ComponentsTests {
    @Test("PosterCard hides the adult badge unless asked")
    func posterCardDefaults() {
        #expect(PosterCard(title: "A", imageURL: nil).isAdult == false)
        #expect(PosterCard(title: "A", imageURL: nil, isAdult: true).isAdult)
    }

    @Test("a toast without an action carries no button")
    func toastDefaults() {
        let plain = ToastView(message: "Sin conexión")
        #expect(plain.actionTitle == nil)
        #expect(plain.action == nil)
        let actionable = ToastView(message: "Error", actionTitle: "Reintentar") {}
        #expect(actionable.actionTitle == "Reintentar")
        #expect(actionable.action != nil)
    }

    @Test("the retry row keeps its message")
    func retryRow() {
        #expect(InlineRetryRow(message: "Sin conexión") {}.message == "Sin conexión")
    }
}
