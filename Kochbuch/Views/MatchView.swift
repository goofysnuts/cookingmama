import SwiftUI

/// Eine Zutat, die man gerade da hat (Menge optional)
struct HaveItem: Codable, Identifiable, Equatable {
  var id = UUID()
  var name: String
  var quantity: String = ""
  var unit: String = ""
}

/// „Was habe ich da?“ – vorhandene Zutaten eingeben und passende Rezepte finden.
/// Die Liste bleibt auf dem Gerät gespeichert, bis man sie leert.
struct MatchView: View {
  @Environment(AppModel.self) private var app

  @AppStorage("match.items") private var storedItems: Data = Data()
  @AppStorage("match.basics") private var assumeBasics = true
  @AppStorage("match.onlyComplete") private var onlyComplete = false

  @State private var items: [HaveItem] = []
  @State private var name = ""
  @State private var quantity = ""
  @State private var unit = ""
  @State private var result: MatchResponse?
  @State private var loading = false
  @State private var error: String?
  @State private var loaded = false
  @State private var confirmClear = false

  private var shown: [RecipeSummary] {
    guard let result else { return [] }
    return onlyComplete ? result.recipes.filter { $0.match?.complete == true } : result.recipes
  }

  var body: some View {
    List {
      Section {
        IngredientNameField(title: "Zutat, z. B. Eier, Mehl, Tomaten", text: $name) { picked in
          if unit.isEmpty { unit = picked.unit }
        }
        .onSubmit { add() }
        HStack {
          TextField("Menge (optional)", text: $quantity).keyboardType(.decimalPad)
          TextField("Einheit", text: $unit).textInputAutocapitalization(.never).frame(maxWidth: 90)
          Button {
            add()
          } label: {
            Image(systemName: "plus.circle.fill").font(.title2)
          }
          .buttonStyle(.borderless)
          .disabled(name.trimmed.isEmpty)
        }
      } header: {
        Text("Was hast du da?")
      } footer: {
        Text("Ohne Menge zählt die Zutat einfach als vorhanden. Mit Menge (in der Einheit des Rezepts) prüft die App, ob es reicht.")
      }

      if !items.isEmpty {
        Section {
          ForEach(items) { item in
            HStack {
              Text(item.name)
              Spacer()
              if !item.quantity.isEmpty {
                Text("\(item.quantity) \(item.unit)").foregroundStyle(.secondary)
              }
            }
          }
          .onDelete { offsets in
            items.remove(atOffsets: offsets)
            save()
          }
          Button("Alle entfernen", role: .destructive) { confirmClear = true }
        } header: {
          Text("Deine Zutaten (\(items.count))")
        }
      }

      Section {
        Toggle("Salz, Pfeffer, Wasser, Zucker und Öl sind da", isOn: $assumeBasics)
        Toggle("Nur Rezepte, für die alles da ist", isOn: $onlyComplete)
      }

      if !items.isEmpty {
        Section {
          if loading, result == nil {
            ProgressView().frame(maxWidth: .infinity)
          } else if let error {
            Text(error).foregroundStyle(.red)
          } else if shown.isEmpty {
            Text(onlyComplete
              ? "Für kein Rezept ist alles da. Schalte „Nur Rezepte, für die alles da ist“ aus, um Rezepte mit wenigen fehlenden Zutaten zu sehen."
              : "Kein Rezept enthält diese Zutaten.")
              .foregroundStyle(.secondary)
          } else {
            ForEach(shown) { r in
              NavigationLink {
                RecipeDetailView(recipeId: r.id)
              } label: {
                RecipeRow(recipe: r)
              }
            }
          }
        } header: {
          if let result {
            Text("Passende Rezepte – \(result.completeCount) komplett kochbar")
          } else {
            Text("Passende Rezepte")
          }
        }
      }
    }
    .navigationTitle("Was habe ich da?")
    .scrollDismissesKeyboard(.interactively)
    .onAppear {
      if !loaded {
        items = (try? JSONDecoder().decode([HaveItem].self, from: storedItems)) ?? []
        loaded = true
      }
    }
    .task(id: searchKey) {
      guard loaded else { return }
      try? await Task.sleep(for: .milliseconds(250))
      if Task.isCancelled { return }
      await search()
    }
    .refreshable { await search() }
    .confirmationDialog("Alle Zutaten entfernen?", isPresented: $confirmClear, titleVisibility: .visible) {
      Button("Entfernen", role: .destructive) {
        items = []
        result = nil
        save()
      }
    }
  }

  private var searchKey: String {
    items.map { "\($0.name)|\($0.quantity)|\($0.unit)" }.joined(separator: ";") + "|\(assumeBasics)|\(loaded)|\(app.revision)"
  }

  private func add() {
    let n = name.trimmed
    guard !n.isEmpty else { return }
    if let index = items.firstIndex(where: { $0.name.lowercased() == n.lowercased() }) {
      items[index].quantity = quantity.trimmed
      items[index].unit = unit.trimmed
    } else {
      items.append(HaveItem(name: n, quantity: quantity.trimmed, unit: unit.trimmed))
    }
    name = ""; quantity = ""; unit = ""
    save()
  }

  private func save() {
    storedItems = (try? JSONEncoder().encode(items)) ?? Data()
  }

  private func search() async {
    struct Item: Encodable { let name: String; let quantity: Double?; let unit: String? }
    struct Payload: Encodable { let items: [Item]; let basics: Bool }
    guard !items.isEmpty else { result = nil; return }
    loading = true
    defer { loading = false }
    do {
      let payload = Payload(
        items: items.map { Item(name: $0.name, quantity: Fmt.parse($0.quantity), unit: $0.unit.nilIfEmpty) },
        basics: assumeBasics
      )
      result = try await app.client.send("POST", "recipes/match", body: payload)
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }
}
