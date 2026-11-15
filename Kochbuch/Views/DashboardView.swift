import SwiftUI

struct DashboardView: View {
  @Environment(AppModel.self) private var app
  @State private var data: Dashboard?
  @State private var error: String?
  @State private var includeIncomplete = false

  var body: some View {
    List {
      if let data {
        Section {
          VStack(alignment: .leading, spacing: 4) {
            Text(data.greeting).font(.title2.bold())
            Text("Vorschläge für \(data.mealTypeLabel) aus deinem Vorrat")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }

        if data.pendingAutoCount > 0 {
          Section {
            NavigationLink {
              AutoRecipesView()
            } label: {
              Label("\(data.pendingAutoCount) automatische Rezept-Anfrage\(data.pendingAutoCount == 1 ? "" : "n") offen", systemImage: "sparkles")
            }
          }
        }

        if !data.favorites.isEmpty {
          Section("Favoriten für \(data.mealTypeLabel)") {
            ForEach(data.favorites) { r in
              NavigationLink(value: r.id) { RecipeRow(recipe: r, showMissing: true) }
            }
          }
        }

        Section {
          Picker("Anzeige", selection: $includeIncomplete) {
            Text("Sofort kochbar").tag(false)
            Text("Auch mit fehlenden Zutaten").tag(true)
          }
          .pickerStyle(.segmented)
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets())

          if data.suggestions.isEmpty {
            Text(includeIncomplete
              ? "Für \(data.mealTypeLabel) gibt es noch keine passenden Rezepte."
              : "Mit deinem Vorrat ist gerade nichts für \(data.mealTypeLabel) komplett kochbar.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(data.suggestions) { r in
              NavigationLink(value: r.id) { RecipeRow(recipe: r, showMissing: true) }
            }
          }
        } header: {
          Text("Vorschläge")
        }

        if !data.recentlyCooked.isEmpty {
          Section("Zuletzt gekocht/gebacken") {
            ForEach(data.recentlyCooked) { entry in
              if let recipe = entry.recipe {
                NavigationLink(value: recipe.id) {
                  HStack(spacing: 12) {
                    RecipeThumb(path: recipe.imageUrl, isBaking: recipe.recipeType == "backen", size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                      Text("\(entry.user.username) \(recipe.recipeType == "backen" ? "hat gebacken" : "hat gekocht")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                      Text(recipe.title).font(.subheadline.weight(.medium))
                      Text(Fmt.relative(entry.at)).font(.caption2).foregroundStyle(.tertiary)
                    }
                  }
                }
              }
            }
          }
        }
      } else if let error {
        ErrorBanner(message: error) { await load() }
      } else {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
    .navigationTitle("Kochbuch")
    .navigationDestination(for: String.self) { id in RecipeDetailView(recipeId: id) }
    .refreshable { await load() }
    .task(id: "\(includeIncomplete)-\(app.revision)") { await load() }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          RecipeEditorView(recipe: nil)
        } label: {
          Image(systemName: "plus")
        }
      }
    }
  }

  private func load() async {
    do {
      data = try await app.client.get("dashboard", query: ["all": includeIncomplete ? "1" : nil])
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }
}
