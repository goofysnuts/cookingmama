import SwiftUI

struct DashboardView: View {
  @Environment(AppModel.self) private var app
  @State private var data: Dashboard?
  @State private var suggestion: RecipeSummary?
  @State private var error: String?
  @State private var shuffling = false

  var body: some View {
    List {
      if let data {
        Section {
          VStack(alignment: .leading, spacing: 4) {
            Text(data.greeting).font(.title2.bold())
            Text("Zeit für \(data.mealTypeLabel)")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
          .listRowBackground(Color.clear)
          .listRowInsets(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
        }

        Section {
          if let suggestion {
            NavigationLink {
              RecipeDetailView(recipeId: suggestion.id)
            } label: {
              SuggestionCard(recipe: suggestion)
            }
            Button {
              Task { await shuffle() }
            } label: {
              HStack {
                Label("Anderer Vorschlag", systemImage: "dice")
                if shuffling { Spacer(); ProgressView() }
              }
            }
            .disabled(shuffling || data.mealRecipeCount < 2)
          } else {
            Text("Für \(data.mealTypeLabel) gibt es noch kein passendes Rezept. Lege eines an oder gib bei den Rezepten „\(data.mealTypeLabel)“ als Mahlzeit an.")
              .foregroundStyle(.secondary)
          }
        } header: {
          Text("Vorschlag für \(data.mealTypeLabel)")
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
          Section("Deine Favoriten für \(data.mealTypeLabel)") {
            ForEach(data.favorites) { r in
              NavigationLink { RecipeDetailView(recipeId: r.id) } label: { RecipeRow(recipe: r) }
            }
          }
        }

        let more = data.moreForMeal.filter { $0.id != suggestion?.id }
        if !more.isEmpty {
          Section("Passt auch zu \(data.mealTypeLabel)") {
            ForEach(more) { r in
              NavigationLink { RecipeDetailView(recipeId: r.id) } label: { RecipeRow(recipe: r) }
            }
          }
        }

        if !data.recentlyCooked.isEmpty {
          Section("Zuletzt gekocht/gebacken") {
            ForEach(data.recentlyCooked) { entry in
              if let recipe = entry.recipe {
                NavigationLink {
                  RecipeDetailView(recipeId: recipe.id)
                } label: {
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
    .refreshable { await load() }
    .task(id: app.revision) { await load() }
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
      let d: Dashboard = try await app.client.get("dashboard")
      data = d
      suggestion = d.suggestion
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func shuffle() async {
    guard let data else { return }
    shuffling = true
    defer { shuffling = false }
    if let res: RandomResponse = try? await app.client.get("recipes/random", query: ["meal": data.mealType, "exclude": suggestion?.id]),
       let recipe = res.recipe {
      withAnimation { suggestion = recipe }
    }
  }
}

/// Große Karte für den Zufallsvorschlag
struct SuggestionCard: View {
  @Environment(AppModel.self) private var app
  let recipe: RecipeSummary

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      RemoteImage(url: app.client.mediaURL(recipe.imageUrl)) {
        ZStack {
          Color.accentColor.opacity(0.12)
          Image(systemName: recipe.isBaking ? "birthday.cake" : "fork.knife")
            .font(.system(size: 44))
            .foregroundStyle(Color.accentColor)
        }
      }
      .frame(height: 170)
      .frame(maxWidth: .infinity)
      .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

      Text(recipe.title).font(.title3.bold())
      if let d = recipe.description, !d.isEmpty {
        Text(d).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
      }
      HStack(spacing: 10) {
        if let category = recipe.category { Pill(text: category.label, color: .brown) }
        if let prep = recipe.prepMinutes { Label(Fmt.minutes(prep), systemImage: "clock") }
        if recipe.totalRestMinutes > 0 { Label(Fmt.minutes(recipe.totalRestMinutes), systemImage: "hourglass") }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(.vertical, 4)
  }
}
