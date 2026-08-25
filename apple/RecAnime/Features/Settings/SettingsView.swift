import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// Account, notifications, Watch, data and about.
struct SettingsView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppDependencies.apiOverrideKey) private var apiOverride = ""
    @AppStorage("ra.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("ra.notifications.offset") private var notificationOffset = 0
    @State private var confirmSignOut = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Cuenta") {
                    if let user = deps.session?.user {
                        LabeledContent(user.name ?? "Cuenta", value: user.email)
                        Button("Cerrar sesión", role: .destructive) { confirmSignOut = true }
                    } else {
                        Label("Modo desarrollo: sin inicio de sesión", systemImage: "hammer")
                            .foregroundStyle(.secondary)
                    }
                }
                Section("Notificaciones") {
                    Toggle("Avisar de nuevos episodios", isOn: $notificationsEnabled)
                    Picker("Momento del aviso", selection: $notificationOffset) {
                        Text("Al emitirse").tag(0)
                        Text("15 min después").tag(15)
                        Text("1 h después").tag(60)
                    }
                    .disabled(!notificationsEnabled)
                }
                Section("Datos") {
                    LabeledContent("Series en tu lista", value: "\(library.items.count)")
                    Button("Vaciar caché de imágenes") { URLCache.shared.removeAllCachedResponses() }
                }
                Section("Acerca de") {
                    LabeledContent(
                        "Versión",
                        value: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))"
                    )
                    LabeledContent("Entorno", value: deps.config.environment.rawValue)
                    LabeledContent("API", value: deps.config.apiBaseURL.absoluteString).lineLimit(1)
                    #if DEBUG
                        TextField("URL de la API (override, requiere reiniciar)", text: $apiOverride)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                    #endif
                }
            }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .confirmationDialog("¿Cerrar sesión en todos tus dispositivos?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Cerrar sesión", role: .destructive) {
                    Task {
                        await deps.session?.signOut()
                        GoogleSignInCoordinator.signOut()
                        dismiss()
                    }
                }
            }
        }
    }
}
