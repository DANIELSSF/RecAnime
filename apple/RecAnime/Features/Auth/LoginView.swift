import RecAnimeKit
import RecAnimeUI
import SwiftUI
import UIKit

/// Full-screen sign in: one glass button over a soft accent glow.
struct LoginView: View {
    @Environment(AppDependencies.self) private var deps
    let message: String?
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            RadialGradient(colors: [Theme.accent.opacity(0.55), .clear], center: .init(x: 0.5, y: 0.18), startRadius: 0, endRadius: 320)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                appGlyph
                Text("RecAnime")
                    .font(.largeTitle.bold())
                    .padding(.top, 28)
                Text("Tu seguimiento de anime, en el bolsillo y en la muñeca.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, Theme.Spacing.s)
                    .padding(.horizontal, Theme.Spacing.xxl)
                if let message {
                    Text(message)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, Theme.Spacing.l)
                }
                Spacer()
                VStack(spacing: Theme.Spacing.l) {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack(spacing: 10) {
                            if isSigningIn {
                                ProgressView().tint(.primary)
                            } else {
                                GoogleLogo().frame(width: 20, height: 20)
                            }
                            Text("Continuar con Google").font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.white)
                    .foregroundStyle(Color.black)
                    .controlSize(.large)
                    .disabled(isSigningIn)
                    Text("Solo para las dos cuentas autorizadas. Los datos de anime provienen de MyAnimeList vía Jikan.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.xxl)
            }
        }
        .alert("No se pudo iniciar sesión", isPresented: Binding(get: { errorMessage != nil }, set: {
            if !$0 {
                errorMessage = nil
            }
        })) {
            Button("Entendido", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var appGlyph: some View {
        Image(systemName: "bookmark.fill")
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 96, height: 96)
            .background(Theme.heroGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Theme.accent.opacity(0.35), radius: 24, y: 12)
            .accessibilityHidden(true)
    }

    private func signIn() async {
        guard let session = deps.session else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let tokens = try await GoogleSignInCoordinator.signIn()
            _ = try await session.signInWithGoogle(idToken: tokens.idToken, accessToken: tokens.accessToken)
            do {
                _ = try await deps.api.me()
            } catch {
                // A rejected account is already signed out by the API's revocation hook and the login screen
                // shows the reason. Any other failure (offline, server hiccup) would make the Watch mint fail
                // too: the Watch asks for a session later, when the phone is reachable.
                return
            }
            Task { await deps.watchSync.mintSession(idToken: tokens.idToken, accessToken: tokens.accessToken) }
        } catch is CancellationError {
            // User dismissed the Google sheet.
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Google "G" from the GoogleSignIn SDK resource bundle (the official asset), with a text fallback.
struct GoogleLogo: View {
    private static let image: UIImage? = {
        guard let url = Bundle.main.url(forResource: "GoogleSignIn_GoogleSignIn", withExtension: "bundle"),
              let bundle = Bundle(url: url) else { return nil }
        return UIImage(named: "google", in: bundle, with: nil)
    }()

    var body: some View {
        if let image = Self.image {
            Image(uiImage: image).resizable().scaledToFit().accessibilityHidden(true)
        } else {
            Text("G").font(.headline.weight(.bold)).foregroundStyle(Color(red: 0.26, green: 0.52, blue: 0.96)) // Google brand blue (allowed)
        }
    }
}
