import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI
import UIKit

/// Account, notifications, Watch, data and about.
struct SettingsView: View {
    @Environment(AppDependencies.self) private var deps
    @Environment(LibraryStore.self) private var library
    @Environment(NotificationCoordinator.self) private var notifications
    @Environment(PhoneWatchSync.self) private var watchSync
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppDependencies.apiOverrideKey) private var apiOverride = ""
    @AppStorage("ra.notifications.enabled") private var notificationsEnabled = true
    @AppStorage("ra.notifications.offset") private var notificationOffset = 0
    @State private var confirmSignOut = false
    /// Server-side content settings; nil while `GET /v1/me` is in flight.
    @State private var settings: RecAnimeCore.Settings?
    @State private var settingsError: String?

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
                Section("Contenido") {
                    if let settings {
                        Toggle("Ocultar contenido adulto", isOn: Binding(get: { settings.sfw }, set: { setSFW($0) }))
                        LabeledContent("Zona horaria", value: settings.timezone)
                        Text("Los datos vienen de MyAnimeList; los títulos +18 se ocultan de las listas y se marcan en la ficha.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: Theme.Spacing.m) {
                            ProgressView()
                            Text("Cargando ajustes…").foregroundStyle(.secondary)
                        }
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
                    LabeledContent("Programadas", value: "\(notifications.pendingCount)")
                    if let next = notifications.nextFire {
                        LabeledContent(
                            "Próxima",
                            value: "\(next.title.replacingOccurrences(of: "Nuevo episodio: ", with: "")) · \(next.fireDate.formatted(date: .abbreviated, time: .shortened))"
                        )
                        .lineLimit(2)
                    }
                    if notificationsEnabled, !notifications.authorized, notifications.lastPlannedAt != nil {
                        Button("Abrir ajustes del sistema") {
                            if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
                .onChange(of: notificationsEnabled) { _, _ in Task { await notifications.replan() } }
                .onChange(of: notificationOffset) { _, _ in Task { await notifications.replan() } }
                Section("Apple Watch") {
                    LabeledContent("Emparejado", value: watchSync.isPaired ? "Sí" : "No")
                    LabeledContent("App instalada", value: watchSync.isWatchAppInstalled ? "Sí" : "No")
                    if let last = watchSync.lastSyncAt {
                        LabeledContent("Última sincronización", value: last.formatted(date: .omitted, time: .shortened))
                    }
                    Button("Sincronizar ahora") {
                        Task {
                            if deps.session != nil {
                                await watchSync.remintSilently()
                            } else {
                                await watchSync.pushSnapshot()
                            }
                        }
                    }
                    if let error = watchSync.lastError {
                        Text(error).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Datos") {
                    LabeledContent("Series en tu lista", value: "\(library.items.count)")
                    Button("Vaciar caché de imágenes") {
                        URLCache.shared.removeAllCachedResponses()
                        Task { await ImageLoader.shared.clear() }
                    }
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
            .task { await loadSettings() }
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .confirmationDialog("¿Cerrar sesión en todos tus dispositivos?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Cerrar sesión", role: .destructive) {
                    Task {
                        await deps.session?.signOut()
                        GoogleSignInCoordinator.signOut()
                        notifications.cancelAll()
                        watchSync.sendSignedOut()
                        await deps.resetLocalData()
                        dismiss()
                    }
                }
            }
            .alert("No se pudo guardar", isPresented: Binding(get: { settingsError != nil }, set: {
                if !$0 {
                    settingsError = nil
                }
            })) {
                Button("Entendido", role: .cancel) {}
            } message: { Text(settingsError ?? "") }
        }
    }

    /// Reads the account settings and, silently, brings the server's timezone in line with the
    /// device's — the API renders airing days in it, so a stale zone shifts the whole calendar.
    private func loadSettings() async {
        guard settings == nil else { return }
        guard let loaded = try? await deps.api.me().settings else { return }
        settings = loaded
        let current = TimeZone.current.identifier
        guard loaded.timezone != current else { return }
        if let updated = try? await deps.api.updateSettings(SettingsPatch(timezone: current)) {
            settings = updated
        }
    }

    /// Optimistic toggle: the switch moves at once and rolls back with an alert if the PATCH fails.
    private func setSFW(_ value: Bool) {
        let previous = settings
        settings?.sfw = value
        Task {
            do {
                settings = try await deps.api.updateSettings(SettingsPatch(sfw: value))
            } catch {
                settings = previous
                settingsError = (error as? APIError)?.userMessage ?? error.localizedDescription
            }
        }
    }
}
