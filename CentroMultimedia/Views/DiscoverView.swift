import SwiftUI

struct DiscoverView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var settings: AppSettings
    @State private var search = ""
    @State private var category: CatalogCategory?
    @State private var duration: CatalogDuration?
    @State private var selected: CatalogEntry?
    @State private var showAdd = false

    private var filtered: [CatalogEntry] {
        library.allCatalogEntries.filter { e in
            (!settings.onlySpanishCatalog || e.inSpanish || e.isCustom)
                && (category == nil || e.categories.contains(category!))
                && (duration == nil || e.duration == duration || e.duration == .mixed)
                && (search.isEmpty || e.name.localizedCaseInsensitiveContains(search)
                    || e.summary.localizedCaseInsensitiveContains(search)
                    || e.topics.contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    private var favorites: [CatalogEntry] {
        library.allCatalogEntries.filter { library.favoriteCatalogIDs.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Chip(title: "Solo castellano", icon: "character.bubble", on: settings.onlySpanishCatalog) {
                                settings.onlySpanishCatalog.toggle()
                            }
                            Chip(title: "Todo", icon: "square.grid.2x2", on: category == nil) { category = nil }
                            ForEach(CatalogCategory.allCases.filter { $0 != .other }) { c in
                                Chip(title: c.rawValue, icon: c.icon, on: category == c) { category = (category == c ? nil : c) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Picker("Duración", selection: $duration) {
                        Text("Cualquier duración").tag(CatalogDuration?.none)
                        ForEach(CatalogDuration.allCases.filter { $0 != .mixed }) { Text($0.rawValue).tag(CatalogDuration?.some($0)) }
                    }
                }

                if !favorites.isEmpty && search.isEmpty && category == nil {
                    Section("Mis favoritos") {
                        ForEach(favorites) { e in CatalogRow(entry: e) { selected = e } }
                    }
                }

                let groups = CatalogCategory.allCases.filter { c in category == nil || c == category }
                ForEach(groups) { c in
                    let entries = filtered.filter { $0.categories.first == c || (category == c && $0.categories.contains(c)) }
                    if !entries.isEmpty {
                        Section {
                            ForEach(entries) { e in CatalogRow(entry: e) { selected = e } }
                        } header: {
                            Label(c.rawValue, systemImage: c.icon)
                        }
                    }
                }

                Section {
                    Text("Todo lo que aparece aquí es gratuito y legal. La oferta de cada servicio cambia con frecuencia y alguno puede pedir registro o mostrar anuncios: lo indicamos en cada ficha.")
                        .font(.footnote).foregroundColor(.secondary)
                }
            }
            .navigationTitle("Descubrir")
            .searchable(text: $search, prompt: "Buscar temática, servicio…")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Añadir enlace propio")
                }
            }
            .sheet(item: $selected) { CatalogDetailView(entry: $0) }
            .sheet(isPresented: $showAdd) { AddCustomEntryView() }
            .withMiniPlayer()
        }
    }
}

struct Chip: View {
    let title: String
    let icon: String
    let on: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? Color.orange : Color(.secondarySystemBackground), in: Capsule())
                .foregroundColor(on ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct CatalogRow: View {
    @EnvironmentObject private var library: LibraryStore
    let entry: CatalogEntry
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.categories.first?.icon ?? "link")
                    .font(.title3).foregroundColor(.orange).frame(width: 30)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.name).font(.headline).foregroundColor(.primary)
                        if library.favoriteCatalogIDs.contains(entry.id) {
                            Image(systemName: "star.fill").font(.caption).foregroundColor(.yellow)
                        }
                    }
                    Text(entry.summary).font(.subheadline).foregroundColor(.secondary).lineLimit(2)
                    Text(entry.languages.joined(separator: " · ") + " · " + entry.duration.rawValue)
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
        }
        .swipeActions {
            Button { library.toggleCatalogFavorite(entry) } label: { Image(systemName: "star") }.tint(.yellow)
            if entry.isCustom {
                Button(role: .destructive) { library.deleteCustomEntry(entry) } label: { Image(systemName: "trash") }
            }
        }
    }
}

struct CatalogDetailView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let entry: CatalogEntry

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(entry.summary)
                    Button {
                        openURL(entry.url)
                    } label: {
                        Label("Abrir \(entry.name)", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowBackground(Color.clear)
                }
                Section("Ficha") {
                    LabeledContent("Idiomas", value: entry.languages.joined(separator: ", "))
                    LabeledContent("Duración", value: entry.duration.rawValue)
                    if !entry.topics.isEmpty { LabeledContent("Temáticas", value: entry.topics.joined(separator: ", ")) }
                    LabeledContent("¿Registro?", value: entry.registration)
                    LabeledContent("Limitaciones", value: entry.limitations)
                    LabeledContent("Enlace", value: entry.url.host ?? entry.url.absoluteString)
                }
                Section {
                    Button {
                        library.toggleCatalogFavorite(entry)
                    } label: {
                        Label(library.favoriteCatalogIDs.contains(entry.id) ? "Quitar de favoritos" : "Guardar en favoritos",
                              systemImage: library.favoriteCatalogIDs.contains(entry.id) ? "star.slash" : "star")
                    }
                    ShareLink(item: entry.url) { Label("Compartir enlace", systemImage: "square.and.arrow.up") }
                }
            }
            .navigationTitle(entry.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

struct AddCustomEntryView: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var link = ""
    @State private var notes = ""
    @State private var category: CatalogCategory = .documentaries

    private var url: URL? {
        let t = link.trimmingCharacters(in: .whitespaces)
        return URL(string: t.lowercased().hasPrefix("http") ? t : "https://" + t)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Nombre (p. ej. un documental de RTVE Play)", text: $name)
                TextField("Enlace", text: $link).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                Picker("Categoría", selection: $category) {
                    ForEach(CatalogCategory.allCases) { Text($0.rawValue).tag($0) }
                }
                TextField("Notas", text: $notes, axis: .vertical)
            }
            .navigationTitle("Añadir enlace")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        if let u = url { library.addCustomEntry(name: name, url: u, category: category, notes: notes) }
                        dismiss()
                    }
                    .disabled(name.isEmpty || link.isEmpty || url == nil)
                }
            }
        }
    }
}

/// Hoja con los servicios de una categoría (se usa desde Música).
struct FreeSourcesSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let category: CatalogCategory
    @State private var selected: CatalogEntry?

    var body: some View {
        NavigationStack {
            List(library.allCatalogEntries.filter { $0.categories.contains(category) }) { e in
                CatalogRow(entry: e) { selected = e }
            }
            .navigationTitle(category.rawValue + " gratis")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Listo") { dismiss() } } }
            .sheet(item: $selected) { CatalogDetailView(entry: $0) }
        }
    }
}
