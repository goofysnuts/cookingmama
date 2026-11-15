import SwiftUI

struct RecipesView: View {
  @Environment(AppModel.self) private var app
  @State private var data: RecipeListResponse?
  @State private var error: String?
  @State private var search = ""
  @State private var diet: String = ""  // "" = Kontoeinstellung, "alle", "vegan", "vegetarisch"
  @State private var type: String = ""
  @State private var meal: String = ""
  @State private var favoritesOnly = false
  @State private var randomId: String?
  @State private var alert: AlertMessage?

  private var filterKey: String { "\(search)|\(diet)|\(type)|\(meal)|\(favoritesOnly)|\(app.revision)" }

  var body: some View {
    List {
      if let data {
        if data.pendingAutoCount > 0 {
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
          NavigationLink(value: r.id) { RecipeRow(recipe: r) }
        }
      } else if let error {
        ErrorBanner(message: error) { await load() }
      } else {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
    .listStyle(.plain)
    .navigationTitle("Rezepte")
    .navigationDestination(for: String.self) { id in RecipeDetailView(recipeId: id) }
    .navigationDestination(item: $randomId) { id in RecipeDetailView(recipeId: id) }
    .searchable(text: $search, prompt: "Rezept, Zutat oder #tag")
    .refreshable { await load() }
    .task(id: filterKey) {
      if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
      if Task.isCancelled { return }
      await load()
    }
    .alertMessage($alert)
    .toolbar {
      ToolbarItem(placement: .topBarLeading) { filterMenu }
      ToolbarItemGroup(placement: .topBarTrailing) {
        Button {
          Task { await random() }
        } label: {
          Image(systemName: "dice")
        }
        Menu {
          NavigationLink {
            RecipeEditorView(recipe: nil)
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
