import SwiftUI

/// Namespace shared by a tab's NavigationStack so posters can zoom into the detail page.
extension EnvironmentValues {
    @Entry var zoomNamespace: Namespace.ID?
}

/// Marks a poster/row as the origin of the zoom transition to `Route.anime(_, source:)`.
struct ZoomSourceModifier: ViewModifier {
    let id: String
    let cornerRadius: CGFloat
    @Environment(\.zoomNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace {
            content.matchedTransitionSource(id: id, in: namespace) { source in
                source.clipShape(.rect(cornerRadius: cornerRadius))
            }
        } else {
            content
        }
    }
}

/// Applies the zoom transition on the destination when a source exists (and motion is not reduced).
struct ZoomDestinationModifier: ViewModifier {
    let sourceID: String?
    @Environment(\.zoomNamespace) private var namespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let sourceID, let namespace, !reduceMotion {
            content.navigationTransition(.zoom(sourceID: sourceID, in: namespace))
        } else {
            content.navigationTransition(.automatic)
        }
    }
}

extension View {
    func zoomSource(_ id: String, cornerRadius: CGFloat = 12) -> some View {
        modifier(ZoomSourceModifier(id: id, cornerRadius: cornerRadius))
    }

    func zoomDestination(sourceID: String?) -> some View {
        modifier(ZoomDestinationModifier(sourceID: sourceID))
    }
}
