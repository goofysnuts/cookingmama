import SwiftUI

/// Übersicht aller Kategorien als Kacheln – Tippen zeigt die Rezepte darin
struct CategoriesView: View {
  @Environment(AppModel.self) private var app
  @State private var alert: AlertMessage?
  @State private var editing: CategoryEditTarget?
  @State private var deleteTarget: RecipeCategory?
  @State private var search = ""

  private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

  private var filtered: [RecipeCategory] {
    let q = search.trimmed.lowercased()
    guard !q.isEmpty else { return app.categories }
    return app.categories.filter { $0.name.lowercased().contains(q) }
  }

  var body: some View {
    ScrollView {
      LazyVGrid(columns: columns, spacing: 12) {
        if search.isEmpty {
          NavigationLink {
            RecipesView(fixedCategory: .all)
          } label: {
            tile(icon: "📖", name: "Alle Rezepte", count: app.categories.reduce(app.uncategorizedCount) { $0 + $1.recipeCount })
          }
        }
        ForEach(filtered) { c in
          NavigationLink {
            RecipesView(fixedCategory: .category(c.ref))
          } label: {
            tile(icon: c.icon ?? "🍽️", name: c.name, count: c.recipeCount)
          }
          .contextMenu {
            if app.isAdmin {
              Button { editing = .edit(c) } label: { Label("Bearbeiten", systemImage: "pencil") }
              Button(role: .destructive) { deleteTarget = c } label: { Label("Löschen", systemImage: "trash") }
            }
          }
        }
        if search.isEmpty, app.uncategorizedCount > 0 {
          NavigationLink {
            RecipesView(fixedCategory: CategoryFilter.none)
          } label: {
            tile(icon: "❔", name: "Ohne Kategorie", count: app.uncategorizedCount)
          }
        }
      }
      .padding()
      if app.isAdmin {
        Text("Tipp: Lange auf eine Kategorie drücken, um sie umzubenennen oder zu löschen.")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .padding(.horizontal)
      }
    }
    .navigationTitle("Kategorien")
    .searchable(text: $search, prompt: "Kategorie suchen")
    .refreshable { await app.reloadCategories() }
    .task { await app.reloadCategories() }
    .alertMessage($alert)
    .toolbar {
      Button { editing = .new } label: { Image(systemName: "plus") }
    }
    .sheet(item: $editing) { target in
      CategoryEditor(target: target)
    }
    .confirmationDialog("Kategorie „\(deleteTarget?.name ?? "")“ löschen?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
      Button("Löschen", role: .destructive) { if let c = deleteTarget { Task { await delete(c) } } }
    } message: {
      Text("Die Rezepte bleiben erhalten und stehen dann unter „Ohne Kategorie“.")
    }
  }

  private func tile(icon: String, name: String, count: Int) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(icon).font(.system(size: 34))
      Text(name)
        .font(.headline)
        .foregroundStyle(Color.primary)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
      Text("\(count) Rezept\(count == 1 ? "" : "e")")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, minHeight: 110, alignment: .topLeading)
    .padding(12)
    .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
  }

  private func delete(_ c: RecipeCategory) async {
    do {
      let res: CategoriesResponse = try await app.client.send("DELETE", "categories/\(c.id)")
      app.apply(res)
      app.didChangeData()
    } catch { alert = .error(error) }
    deleteTarget = nil
  }
}

enum CategoryEditTarget: Identifiable {
  case new
  case edit(RecipeCategory)

  var id: String {
    switch self {
    case .new: return "new"
    case let .edit(c): return c.id
    }
  }
}

/// Neue Kategorie anlegen oder (Admin) bearbeiten
struct CategoryEditor: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let target: CategoryEditTarget
  var onCreated: ((CategoryRef) -> Void)?

  @State private var name = ""
  @State private var icon = ""
  @State private var error: String?
  @State private var busy = false

  private static let suggestions = ["🍞", "🥐", "🎂", "🍪", "🥧", "🍰", "🍮", "🍨", "🥞", "🍳", "🥗", "🍲", "🥣", "🍝", "🍕", "🌮", "🍔", "🥘", "🍛", "🍣", "🥔", "🥦", "🍖", "🐟", "🥫", "🧁", "🍹", "☕️", "🎄", "🌱"]

  var body: some View {
    NavigationStack {
      Form {
        Section("Name") {
          TextField("z. B. Aufläufe", text: $name)
        }
        Section("Symbol") {
          TextField("Emoji", text: $icon)
          ScrollView(.horizontal, showsIndicators: false) {
            HStack {
              ForEach(Self.suggestions, id: \.self) { e in
                Button {
                  icon = e
                } label: {
                  Text(e)
                    .font(.title2)
                    .padding(4)
                    .background(icon == e ? Color.accentColor.opacity(0.25) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
              }
            }
          }
        }
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle(isNew ? "Neue Kategorie" : "Kategorie bearbeiten")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button(isNew ? "Anlegen" : "Sichern") { Task { await save() } }
            .disabled(busy || name.trimmed.isEmpty)
        }
      }
      .onAppear {
        if case let .edit(c) = target {
          name = c.name
          icon = c.icon ?? ""
        }
      }
    }
    .presentationDetents([.medium])
  }

  private var isNew: Bool {
    if case .new = target { return true }
    return false
  }

  private func save() async {
    struct Payload: Encodable { let name: String; let icon: String? }
    busy = true
    defer { busy = false }
    let iconValue = String(icon.trimmed.prefix(2))
    do {
      let res: CategoriesResponse
      switch target {
      case .new:
        res = try await app.client.send("POST", "categories", body: Payload(name: name.trimmed, icon: iconValue.nilIfEmpty))
        if let created = res.created { onCreated?(created) }
      case let .edit(c):
        res = try await app.client.send("PATCH", "categories/\(c.id)", body: Payload(name: name.trimmed, icon: iconValue))
      }
      app.apply(res)
      app.didChangeData()
      dismiss()
    } catch {
      self.error = error.localizedDescription
    }
  }
}
