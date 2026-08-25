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
            .navigationTitle("Ajustes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .confirmationDialog("¿Cerrar sesión en todos tus dispositivos?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Cerrar sesión", role: .destructive) {
                    Task {
                        await deps.session?.signOut()
                        GoogleSignInCoordinator.signOut()
                        notifications.cancelAll()
                        watchSync.sendSignedOut()
                        dismiss()
                    }
                }
            }
        }
    }
}
