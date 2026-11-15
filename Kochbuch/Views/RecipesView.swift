import SwiftUI

/// Kategorie-Filter der Rezeptliste
enum CategoryFilter: Hashable {
  case all
  case none
  case category(CategoryRef)

  var queryValue: String? {
    switch self {
    case .all: return nil
    case .none: return "none"
    case let .category(c): return c.id
    }
  }

  var title: String {
    switch self {
    case .all: return "Rezepte"
    case .none: return "Ohne Kategorie"
    case let .category(c): return c.name
    }
  }
}

struct RecipesView: View {
  @Environment(AppModel.self) private var app
  /// Gesetzt, wenn die Liste aus der Kategorien-Übersicht geöffnet wurde (fester Filter)
  var fixedCategory: CategoryFilter?

  @State private var data: RecipeListResponse?
  @State private var error: String?
  @State private var search = ""
  @State private var diet: String = ""  // "" = Kontoeinstellung, "alle", "vegan", "vegetarisch"
  @State private var type: String = ""
  @State private var meal: String = ""
  @State private var category: CategoryFilter = .all
  @State private var favoritesOnly = false
  @State private var randomId: String?
  @State private var alert: AlertMessage?

  private var activeCategory: CategoryFilter { fixedCategory ?? category }
  private var filterKey: String { "\(search)|\(diet)|\(type)|\(meal)|\(activeCategory)|\(favoritesOnly)|\(app.revision)" }

  var body: some View {
    List {
      if fixedCategory == nil {
        categoryStrip
          .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
          .listRowSeparator(.hidden)
      }
      if let data {
        if fixedCategory == nil, data.pendingAutoCount > 0 {
          NavigationLink {
            AutoRecipesView()
          } label: {
            Label("\(data.pendingAutoCount) automatische Anfrage\(data.pendingAutoCount == 1 ? "" : "n") offen", systemImage: "sparkles")
          }
        }
        if data.recipes.isEmpty {
          ContentUnavailableView("Keine Rezepte gefunden", systemImage: "book.closed", description: Text("Filter ändern oder ein neues Rezept anlegen."))
        }
        ForEach(data.recipes) { r in
          NavigationLink {
            RecipeDetailView(recipeId: r.id)
          } label: {
            RecipeRow(recipe: r, showCategory: activeCategory == .all)
          }
        }
      } else if let error {
        ErrorBanner(message: error) { await load() }
      } else {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
    .listStyle(.plain)
    .navigationTitle(activeCategory.title)
    .navigationDestination(item: $randomId) { id in RecipeDetailView(recipeId: id) }
    .searchable(text: $search, prompt: fixedCategory == nil ? "Rezept, Zutat, Kategorie oder #tag" : "In \(activeCategory.title) suchen")
    .refreshable { await load() }
    .task(id: filterKey) {
      if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
      if Task.isCancelled { return }
      await load()
    }
    .alertMessage($alert)
    .toolbar {
      if fixedCategory == nil {
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink {
            CategoriesView()
          } label: {
            Label("Kategorien", systemImage: "square.grid.2x2")
          }
        }
      }
      ToolbarItemGroup(placement: .topBarTrailing) {
        filterMenu
        if fixedCategory == nil {
          Button {
            Task { await random() }
          } label: {
            Image(systemName: "dice")
          }
        }
        Menu {
          NavigationLink {
            RecipeEditorView(recipe: nil, presetCategory: presetCategory)
          } label: {
            Label("Rezept selbst eingeben", systemImage: "square.and.pencil")
          }
          NavigationLink {
            AutoRecipeNewView()
          } label: {
            Label("Automatisch aus Fotos/PDF", systemImage: "sparkles")
          }
        } label: {
          Image(systemName: "plus")
        }
      }
    }
  }

  private var presetCategory: CategoryRef? {
    if case let .category(c) = activeCategory { return c }
    return nil
  }

  /// Waagrechte Kategorie-Leiste über der Liste
  private var categoryStrip: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        chip("Alle", selected: category == .all) { category = .all }
        ForEach(app.categories.filter { $0.recipeCount > 0 }) { c in
          chip(c.ref.label, selected: category == .category(c.ref)) {
            category = (category == .category(c.ref)) ? .all : .category(c.ref)
          }
        }
        if app.uncategorizedCount > 0 {
          chip("Ohne Kategorie", selected: category == .none) {
            category = (category == .none) ? .all : .none
          }
        }
      }
      .padding(.horizontal, 16)
    }
  }

  private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(selected ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
        .foregroundStyle(selected ? Color.white : Color.primary)
    }
    .buttonStyle(.plain)
  }

  private var activeFilterCount: Int {
    [diet.isEmpty ? 0 : 1, type.isEmpty ? 0 : 1, meal.isEmpty ? 0 : 1, favoritesOnly ? 1 : 0].reduce(0, +)
  }

  private var filterMenu: some View {
    Menu {
      Toggle(isOn: $favoritesOnly) { Label("Nur Favoriten", systemImage: "star") }
      Picker("Art", selection: $type) {
        Text("Alle Arten").tag("")
        Text("Kochrezepte").tag("kochen")
        Text("Backrezepte").tag("backen")
      }
      Picker("Ernährung", selection: $diet) {
        Text("Wie im Konto").tag("")
        Text("Alle").tag("alle")
        Text("Vegetarisch").tag("vegetarisch")
        Text("Vegan").tag("vegan")
      }
      Picker("Mahlzeit", selection: $meal) {
        Text("Alle Mahlzeiten").tag("")
        ForEach(Labels.mealTypes, id: \.self) { Text(Labels.mealType($0)).tag($0) }
      }
      if activeFilterCount > 0 {
        Button("Filter zurücksetzen", role: .destructive) {
          diet = ""; type = ""; meal = ""; favoritesOnly = false
        }
      }
    } label: {
      Image(systemName: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
    }
  }

  private func load() async {
    do {
      data = try await app.client.get("recipes", query: [
        "q": search.nilIfEmpty,
        "diet": diet.nilIfEmpty,
        "type": type.nilIfEmpty,
        "meal": meal.nilIfEmpty,
        "category": activeCategory.queryValue,
        "favorites": favoritesOnly ? "1" : nil,
      ])
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func random() async {
    do {
      let res: RandomResponse = try await app.client.get("recipes/random")
      randomId = res.id
    } catch {
      alert = .error(error)
    }
  }
}
