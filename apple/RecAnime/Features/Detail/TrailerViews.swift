import RecAnimeCore
import RecAnimeUI
import SwiftUI
import WebKit

/// 16:9 thumbnail with a play glyph; opens the in-app trailer sheet.
struct TrailerCard: View {
    let detail: AnimeDetail
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                CachedAsyncImage(url: detail.trailerImageURL ?? detail.imageLargeURL) {
                    Rectangle().fill(Theme.heroGradient.opacity(0.35))
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(16 / 9, contentMode: .fill)
                .frame(height: 190)
                .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack {
                    Spacer()
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: "play.fill")
                            .font(.title3.weight(.bold))
                            .frame(width: 52, height: 52)
                            .foregroundStyle(.white)
                            .background(Theme.accent, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ver tráiler").font(.headline).foregroundStyle(.white)
                            Text("YouTube · se reproduce aquí").font(.caption).foregroundStyle(.white.opacity(0.85))
                        }
                        Spacer()
                    }
                    .padding(Theme.Spacing.l)
                }
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ver tráiler de \(detail.title)")
        .accessibilityIdentifier("detail.trailer")
    }
}

/// Bottom sheet that plays the YouTube embed inline, with a fallback link to YouTube.
struct TrailerSheet: View {
    let detail: AnimeDetail
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let url = detail.trailerEmbedURL, TrailerWebView.isEmbeddable(url) {
                    TrailerWebView(url: url)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.top, Theme.Spacing.m)
                } else {
                    EmptyStateView(title: "Sin tráiler", message: "MyAnimeList no tiene un tráiler para este anime.", systemImage: "play.slash")
                }
                if let external = detail.trailerURL {
                    Link(destination: external) {
                        Label("Abrir en YouTube", systemImage: "arrow.up.right.square")
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                    }
                    .buttonStyle(.glass)
                    .padding(.horizontal, Theme.Spacing.l)
                    .padding(.top, Theme.Spacing.l)
                }
                Spacer(minLength: 0)
            }
            .navigationTitle("Tráiler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

/// WKWebView wrapper configured for inline autoplay. The embed is wrapped in a local page with an
/// https base URL: YouTube refuses direct embed loads without a Referer (player error 153).
struct TrailerWebView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isOpaque = false
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        view.navigationDelegate = context.coordinator
        view.loadHTMLString(Self.page(embedding: url), baseURL: URL(string: "https://recanime.app/"))
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    /// Without this the embed keeps playing (and holding the delegate) after the sheet closes.
    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        if let blank = URL(string: "about:blank") {
            uiView.load(URLRequest(url: blank))
        }
    }

    /// Keeps the sheet on the embed: the local page and YouTube load in place, anything else
    /// (a channel link inside the player, a new window) is cancelled and opened in the browser.
    final class Coordinator: NSObject, WKNavigationDelegate {
        private static let allowedHosts = ["recanime.app", "youtube.com", "youtube-nocookie.com", "youtu.be", "google.com", "doubleclick.net"]

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            let opensNewWindow = navigationAction.targetFrame == nil
            let leavesEmbed = navigationAction.targetFrame?.isMainFrame == true && !Self.isAllowed(url)
            guard opensNewWindow || leavesEmbed else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            // Only a tap on a link may leave the app, and only to a web page: script-driven redirects,
            // pop-ups and custom schemes coming from the embed are dropped silently.
            guard navigationAction.navigationType == .linkActivated,
                  let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return }
            UIApplication.shared.open(url)
        }

        /// Hosts the embed itself needs; everything else counts as navigating away.
        private static func isAllowed(_ url: URL) -> Bool {
            guard let scheme = url.scheme?.lowercased() else { return false }
            if scheme == "about" || scheme == "data" || scheme == "blob" {
                return true
            }
            guard let host = url.host()?.lowercased() else { return false }
            return allowedHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
        }
    }

    /// Only a YouTube embed URL over https is ever written into the local page; the API relays values
    /// from Jikan, so a malformed or foreign URL must not reach the iframe.
    static func isEmbeddable(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host()?.lowercased() else { return false }
        let youtube = ["youtube.com", "youtube-nocookie.com"]
        guard youtube.contains(where: { host == $0 || host.hasSuffix(".\($0)") }) else { return false }
        return url.path().hasPrefix("/embed/")
    }

    static func page(embedding url: URL) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{position:absolute;inset:0;width:100%;height:100%;border:0}</style></head>
        <body><iframe src="\(htmlAttribute(url
                .absoluteString))" title="Tráiler" allow="autoplay; encrypted-media; picture-in-picture" allowfullscreen></iframe></body></html>
        """
    }

    /// Escapes a value for an HTML attribute so it can never terminate the attribute or the tag.
    static func htmlAttribute(_ value: String) -> String {
        var out = ""
        for character in value {
            switch character {
            case "&": out += "&amp;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(character)
            }
        }
        return out
    }
}

/// Bottom sheet with a wheel to jump to an exact episode (one-handed alternative to tapping +N times).
struct EpisodePickerSheet: View {
    let title: String
    let total: Int?
    /// Episode titles keyed by number, when the detail page has them; the wheel then reads "Ep 7 · Título".
    var titles: [Int: String] = [:]
    @State var selection: Int
    let onSave: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.l) {
                Text(title).font(.headline).multilineTextAlignment(.center).padding(.horizontal)
                Picker("Episodio", selection: $selection) {
                    ForEach(0 ... (total ?? max(selection + 50, 100)), id: \.self) { number in
                        Text(label(for: number)).tag(number)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxHeight: 200)
                Button {
                    onSave(selection)
                    dismiss()
                } label: {
                    Text("Guardar").frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .padding(.horizontal, Theme.Spacing.l)
            }
            .padding(.top, Theme.Spacing.m)
            .navigationTitle("Ir al episodio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func label(for number: Int) -> String {
        guard number > 0 else { return "Sin empezar" }
        guard let episodeTitle = titles[number], !episodeTitle.isEmpty else { return "Episodio \(number)" }
        return "Ep \(number) · \(episodeTitle)"
    }
}
