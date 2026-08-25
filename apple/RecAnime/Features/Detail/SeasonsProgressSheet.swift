import RecAnimeCore
import RecAnimeKit
import RecAnimeUI
import SwiftUI

/// "¿Hasta dónde has visto?" — pick a season; everything up to it becomes watched in one request.
struct SeasonsProgressSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let franchise: Franchise
    @State private var selection: Int
    @State private var startNext = true
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(franchise: Franchise, preselected: Int?) {
        self.franchise = franchise
        _selection = State(initialValue: preselected ?? franchise.currentIndex)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(franchise.entries.enumerated()), id: \.element.id) { index, entry in
                        Button {
                            withAnimation(.snappy) { selection = index }
                        } label: {
                            HStack(spacing: Theme.Spacing.m) {
                                Image(systemName: index <= selection ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(index <= selection ? Theme.statusWatched : Color(.tertiaryLabel))
                                    .contentTransition(.symbolEffect(.replace))
                                PosterImage(url: entry.anime?.imageURL, width: 36, height: 54, cornerRadius: Theme.Radius.thumb)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("T\(entry.position) · \(entry.title)").font(.subheadline.weight(.semibold)).lineLimit(2)
                                    if let anime = entry.anime {
                                        MetadataRow([anime.year.map(String.init), anime.episodes.map { "\($0) ep" }, currentLabel(anime)])
                                    } else {
                                        Text("Sin datos · se omitirá").font(.footnote).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 54)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!entry.resolved)
                        .accessibilityIdentifier("progress.row.\(index)")
                        .accessibilityAddTraits(index == selection ? .isSelected : [])
                    }
                } header: {
                    Text("Toca la última temporada que has visto")
                } footer: {
                    Text(summary).font(.footnote)
                }
                if nextEntry != nil {
                    Section {
                        Toggle("Empezar la siguiente ahora", isOn: $startNext)
                    } footer: {
                        Text("Queda en \"Viendo\" con 0 episodios; si prefieres, la dejas en Pendiente.")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        if isSaving {
                            ProgressView().tint(.white)
                        }
                        Text("Guardar").font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
                .disabled(isSaving)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.s)
                .accessibilityIdentifier("progress.save")
            }
            .navigationTitle("Marcar hasta…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } } }
            .alert("No se pudo guardar", isPresented: Binding(get: { errorMessage != nil }, set: {
                if !$0 {
                    errorMessage = nil
                }
            })) {
                Button("Entendido", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var nextEntry: FranchiseEntry? {
        guard selection + 1 < franchise.entries.count else { return nil }
        let next = franchise.entries[selection + 1]
        return next.anime == nil ? nil : next
    }

    private var summary: String {
        let last = franchise.entries[selection]
        var text = selection == 0 ? "T1 → Vista" : "T1–T\(last.position) → Vistas"
        let skipped = franchise.entries.prefix(selection + 1).filter { $0.anime == nil }.count
        if skipped > 0 {
            text += " (\(skipped) sin datos, se omite)"
        }
        if startNext, let next = nextEntry {
            text += " · T\(next.position) → Viendo"
        }
        return text
    }

    private func currentLabel(_ anime: AnimeSummary) -> String? {
        guard let status = library.overlay(for: anime.malId)?.status ?? anime.library?.status else { return nil }
        return status.spanish
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await library.markWatched(through: selection, in: franchise, startNext: startNext && nextEntry != nil)
            dismiss()
        } catch let error as APIError {
            errorMessage = error.userMessage
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
