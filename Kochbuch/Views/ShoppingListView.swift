import SwiftUI

struct ShoppingListView: View {
  @Environment(AppModel.self) private var app
  @State private var items: [ShoppingItem] = []
  @State private var loaded = false
  @State private var error: String?
  @State private var alert: AlertMessage?
  @State private var newName = ""
  @State private var newQuantity = ""
  @State private var newUnit = ""
  @State private var editing: ShoppingItem?
  @FocusState private var nameFocused: Bool

  private var open: [ShoppingItem] { items.filter { !$0.checked } }
  private var done: [ShoppingItem] { items.filter(\.checked) }

  var body: some View {
    List {
      Section {
        IngredientNameField(title: "Was fehlt?", text: $newName) { picked in
          if newUnit.isEmpty { newUnit = picked.purchaseUnit ?? picked.unit }
        }
        HStack {
          TextField("Menge", text: $newQuantity).keyboardType(.decimalPad).frame(maxWidth: 90)
          TextField("Einheit", text: $newUnit).textInputAutocapitalization(.never)
          Button {
            Task { await addItem() }
          } label: {
            Image(systemName: "plus.circle.fill").font(.title2)
          }
          .buttonStyle(.borderless)
          .disabled(newName.trimmed.isEmpty)
        }
      }

      if let error, !loaded {
        ErrorBanner(message: error) { await load() }
      }

      Section {
        if open.isEmpty, loaded {
          Text("Alles erledigt 🎉").foregroundStyle(.secondary)
        }
        ForEach(open) { item in
          row(item)
            .swipeActions(edge: .trailing) {
              Button("Löschen", role: .destructive) { Task { await delete(item) } }
              Button("Ändern") { editing = item }.tint(.blue)
            }
        }
      } header: {
        Text("Offen (\(open.count))")
      } footer: {
        Text("Gemeinsame Liste für alle. Zutaten aus Rezepten kannst du im Rezept über „Auf die Einkaufsliste“ hinzufügen.")
      }

      if !done.isEmpty {
        Section {
          ForEach(done) { item in
            row(item)
              .swipeActions {
                Button("Löschen", role: .destructive) { Task { await delete(item) } }
              }
          }
          Button("Erledigte entfernen", role: .destructive) { Task { await clearChecked() } }
        } header: {
          Text("Erledigt")
        }
      }
    }
    .navigationTitle("Einkaufsliste")
    .refreshable { await load() }
    .task(id: app.revision) { await load() }
    .alertMessage($alert)
    .sheet(item: $editing) { item in
      ShoppingItemEditor(item: item) { updated in items = updated }
    }
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        ShareLink(item: shareText) {
          Image(systemName: "square.and.arrow.up")
        }
      }
    }
  }

  private var shareText: String {
    "Einkaufsliste:\n" + open.map { i in
      "• \(i.name)" + (i.quantity.map { " – \(Fmt.quantity($0, i.unit))" } ?? "")
    }.joined(separator: "\n")
  }

  private func row(_ item: ShoppingItem) -> some View {
    Button {
      Task { await toggle(item) }
    } label: {
      HStack {
        Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(item.checked ? Color.green : Color.secondary)
          .font(.title3)
        VStack(alignment: .leading) {
          Text(item.name).strikethrough(item.checked).foregroundStyle(item.checked ? Color.secondary : Color.primary)
          if let by = item.createdBy {
            Text("von \(by)").font(.caption2).foregroundStyle(.tertiary)
          }
        }
        Spacer()
        if let q = item.quantity {
          Text(Fmt.quantity(q, item.unit)).foregroundStyle(.secondary).monospacedDigit()
        } else if let u = item.unit, !u.isEmpty {
          Text(u).foregroundStyle(.secondary)
        }
      }
    }
    .buttonStyle(.plain)
  }

  private func load() async {
    do {
      let res: ShoppingListResponse = try await app.client.get("shopping-list")
      items = res.items
      loaded = true
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func addItem() async {
    struct Payload: Encodable { let items: [ShoppingItemInput] }
    let input = ShoppingItemInput(name: newName.trimmed, quantity: Fmt.parse(newQuantity), unit: newUnit.nilIfEmpty)
    do {
      let res: ShoppingListResponse = try await app.client.send("POST", "shopping-list/items", body: Payload(items: [input]))
      items = res.items
      newName = ""; newQuantity = ""; newUnit = ""
    } catch { alert = .error(error) }
  }

  private func toggle(_ item: ShoppingItem) async {
    do {
      let res: ShoppingListResponse = try await app.client.send("POST", "shopping-list/items/\(item.id)/\(item.checked ? "uncheck" : "check")")
      withAnimation { items = res.items }
    } catch { alert = .error(error) }
  }

  private func delete(_ item: ShoppingItem) async {
    do {
      let res: ShoppingListResponse = try await app.client.send("DELETE", "shopping-list/items/\(item.id)")
      withAnimation { items = res.items }
    } catch { alert = .error(error) }
  }

  private func clearChecked() async {
    do {
      let res: ShoppingListResponse = try await app.client.send("DELETE", "shopping-list/checked")
      withAnimation { items = res.items }
    } catch { alert = .error(error) }
  }

}

struct ShoppingItemEditor: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let item: ShoppingItem
  let onSaved: ([ShoppingItem]) -> Void
  @State private var name = ""
  @State private var quantity = ""
  @State private var unit = ""
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        TextField("Name", text: $name)
        TextField("Menge", text: $quantity).keyboardType(.decimalPad)
        TextField("Einheit", text: $unit).textInputAutocapitalization(.never)
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle("Eintrag ändern")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Sichern") { Task { await save() } }.disabled(name.trimmed.isEmpty)
        }
      }
      .onAppear {
        name = item.name
        quantity = Fmt.editable(item.quantity)
        unit = item.unit ?? ""
      }
    }
    .presentationDetents([.medium])
  }

  private func save() async {
    do {
      let res: ShoppingListResponse = try await app.client.send(
        "PATCH", "shopping-list/items/\(item.id)",
        body: ShoppingItemInput(name: name.trimmed, quantity: Fmt.parse(quantity), unit: unit.nilIfEmpty)
      )
      onSaved(res.items)
      dismiss()
    } catch {
      self.error = error.localizedDescription
    }
  }
}
