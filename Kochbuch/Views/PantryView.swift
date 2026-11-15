import PhotosUI
import SwiftUI

struct PantryView: View {
  @Environment(AppModel.self) private var app
  @State private var data: PantryResponse?
  @State private var error: String?
  @State private var search = ""
  @State private var diet = ""
  @State private var onlyStocked = false
  @State private var onlyLow = false
  @State private var alert: AlertMessage?
  @State private var quickAdd: PantryEntry?
  @State private var quickAmount = ""

  private var items: [PantryEntry] {
    (data?.items ?? []).filter { item in
      (!onlyStocked || item.stock != nil) && (!onlyLow || item.isLow)
    }
  }

  var body: some View {
    List {
      if let data {
        Section {
          if data.households.count > 1 {
            Menu {
              ForEach(data.households) { h in
                Button {
                  Task { await switchHousehold(h.id) }
                } label: {
                  if h.id == data.activeHousehold?.id { Label(h.name, systemImage: "checkmark") } else { Text(h.name) }
                }
              }
            } label: {
              Label(data.activeHousehold?.name ?? "Haushalt", systemImage: "house")
            }
          } else if let h = data.activeHousehold {
            Label(h.name, systemImage: "house").foregroundStyle(.secondary)
          }
          Button {
            Task { await autoShoppingList() }
          } label: {
            Label("Knappe Zutaten auf die Einkaufsliste", systemImage: "cart.badge.plus")
          }
        }

        Section {
          if items.isEmpty {
            Text("Keine Zutaten gefunden.").foregroundStyle(.secondary)
          }
          ForEach(items) { item in
            NavigationLink {
              PantryEditView(ingredientId: item.ingredientId)
            } label: {
              PantryRow(item: item)
            }
            .swipeActions(edge: .leading) {
              if item.stock?.unlimited != true {
                Button {
                  quickAmount = item.stock?.purchaseQuantity.map { Fmt.editable($0) } ?? ""
                  quickAdd = item
                } label: {
                  Label("Auffüllen", systemImage: "plus")
                }
                .tint(.green)
              }
            }
          }
        } header: {
          Text("\(items.count) Zutaten")
        }
      } else if let error {
        ErrorBanner(message: error) { await load() }
      } else {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
    .navigationTitle("Vorrat")
    .searchable(text: $search, prompt: "Zutat suchen")
    .refreshable { await load() }
    .task(id: "\(search)|\(diet)|\(app.revision)") {
      if !search.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
      if Task.isCancelled { return }
      await load()
    }
    .alertMessage($alert)
    .alert("Auffüllen", isPresented: Binding(get: { quickAdd != nil }, set: { if !$0 { quickAdd = nil } })) {
      TextField("Menge", text: $quickAmount).keyboardType(.decimalPad)
      Button("Hinzufügen") {
        if let item = quickAdd { Task { await add(item) } }
      }
      Button("Abbrechen", role: .cancel) { quickAdd = nil }
    } message: {
      Text("Wie viel \(quickAdd?.unit ?? "") \(quickAdd?.name ?? "") kommt dazu?")
    }
    .toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Menu {
          Toggle("Nur mit Bestand", isOn: $onlyStocked)
          Toggle("Nur knappe", isOn: $onlyLow)
          Picker("Ernährung", selection: $diet) {
            Text("Wie im Konto").tag("")
            Text("Alle").tag("alle")
            Text("Vegetarisch").tag("vegetarisch")
            Text("Vegan").tag("vegan")
          }
        } label: {
          Image(systemName: (onlyStocked || onlyLow || !diet.isEmpty) ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
        }
      }
      ToolbarItem(placement: .topBarTrailing) {
        NavigationLink {
          PantryEditView(ingredientId: nil)
        } label: {
          Image(systemName: "plus")
        }
      }
    }
  }

  private func load() async {
    do {
      data = try await app.client.get("pantry", query: ["q": search.nilIfEmpty, "diet": diet.nilIfEmpty])
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func switchHousehold(_ id: String) async {
    struct Payload: Encodable { let householdId: String }
    do {
      let _: HouseholdsResponse = try await app.client.send("PUT", "households/active", body: Payload(householdId: id))
      app.didChangeData()
    } catch { alert = .error(error) }
  }

  private func autoShoppingList() async {
    do {
      let res: ShoppingListResponse = try await app.client.send("POST", "shopping-list/auto")
      alert = AlertMessage(title: "Einkaufsliste", message: "\(res.added ?? 0) Zutat(en) eingetragen.")
      app.didChangeData()
    } catch { alert = .error(error) }
  }

  private func add(_ item: PantryEntry) async {
    struct Payload: Encodable { let amount: Double }
    guard let amount = Fmt.parse(quickAmount), amount != 0 else { return }
    do {
      let _: PantryEntry = try await app.client.send("POST", "pantry/\(item.ingredientId)/add", body: Payload(amount: amount))
      quickAdd = nil
      await load()
    } catch { alert = .error(error) }
  }
}

struct PantryRow: View {
  @Environment(AppModel.self) private var app
  let item: PantryEntry

  var body: some View {
    HStack(spacing: 12) {
      RemoteImage(url: app.client.mediaURL(item.imageUrl)) {
        ZStack {
          Color.secondary.opacity(0.1)
          Text(String(item.name.prefix(1))).font(.headline).foregroundStyle(.secondary)
        }
      }
      .frame(width: 40, height: 40)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(item.name)
          if item.dietType != "vegan" {
            Image(systemName: item.dietType == "vegetarisch" ? "leaf" : "fish")
              .font(.caption2)
              .foregroundStyle(.secondary)
          }
        }
        if let stock = item.stock {
          if stock.unlimited {
            Text("Unbegrenzt verfügbar").font(.caption).foregroundStyle(.secondary)
          } else {
            Text(Fmt.quantity(stock.quantity, stock.unit)
              + (stock.minQuantity.map { " · min. \(Fmt.number($0))" } ?? "")
              + (stock.isPublic ? "" : " · privat"))
              .font(.caption)
              .foregroundStyle(item.isLow ? Color.orange : Color.secondary)
          }
        } else {
          Text("Kein Vorrat").font(.caption).foregroundStyle(.tertiary)
        }
      }
      Spacer()
      if item.isLow {
        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      }
    }
  }
}

// MARK: - Zutat / Bestand bearbeiten

struct PantryEditView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let ingredientId: String?

  @State private var entry: PantryEntry?
  @State private var name = ""
  @State private var unit = "g"
  @State private var dietType = "vegan"
  @State private var quantity = ""
  @State private var minQuantity = ""
  @State private var purchaseQuantity = ""
  @State private var purchaseUnit = ""
  @State private var purchaseUnitFactor = ""
  @State private var unlimited = false
  @State private var isPublic = false
  @State private var imagePath: String?
  @State private var newImage: UIImage?
  @State private var imageRemoved = false
  @State private var photoItem: PhotosPickerItem?
  @State private var showCamera = false
  @State private var saving = false
  @State private var alert: AlertMessage?
  @State private var confirmDelete = false

  var body: some View {
    Form {
      Section {
        HStack {
          Group {
            if let newImage {
              Image(uiImage: newImage).resizable().scaledToFill()
            } else if let imagePath, !imageRemoved {
              RemoteImage(url: app.client.mediaURL(imagePath)) { Color.secondary.opacity(0.1) }
            } else {
              ZStack {
                Color.secondary.opacity(0.1)
                Image(systemName: "photo").foregroundStyle(.secondary)
              }
            }
          }
          .frame(width: 72, height: 72)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          VStack(alignment: .leading, spacing: 8) {
            PhotosPicker(selection: $photoItem, matching: .images) { Label("Foto wählen", systemImage: "photo") }
            Button { showCamera = true } label: { Label("Aufnehmen", systemImage: "camera") }
            if newImage != nil || (imagePath != nil && !imageRemoved) {
              Button("Foto entfernen", role: .destructive) {
                newImage = nil
                imageRemoved = true
              }
            }
          }
          .buttonStyle(.borderless)
          .font(.callout)
        }
      }

      Section("Zutat") {
        if ingredientId == nil {
          IngredientNameField(title: "Name", text: $name) { picked in
            unit = picked.unit
            dietType = picked.dietType
          }
        } else {
          TextField("Name", text: $name)
        }
        HStack {
          TextField("Einheit", text: $unit).textInputAutocapitalization(.never)
          Menu {
            ForEach(Labels.commonUnits, id: \.self) { u in Button(u) { unit = u } }
          } label: {
            Image(systemName: "chevron.down.circle")
          }
        }
        Picker("Einstufung", selection: $dietType) {
          ForEach(Labels.dietTypes, id: \.self) { Text(Labels.diet($0)).tag($0) }
        }
      }

      Section {
        Toggle("Unbegrenzt verfügbar (z. B. Leitungswasser)", isOn: $unlimited)
        if !unlimited {
          LabeledContent("Bestand") { NumberField(title: "0", text: $quantity, unit: unit).multilineTextAlignment(.trailing) }
          LabeledContent("Mindestbestand") { NumberField(title: "optional", text: $minQuantity, unit: unit).multilineTextAlignment(.trailing) }
          LabeledContent("Nachkaufmenge") { NumberField(title: "optional", text: $purchaseQuantity, unit: unit).multilineTextAlignment(.trailing) }
          Toggle("Für alle im Haushalt sichtbar", isOn: $isPublic)
        }
      } header: {
        Text("Vorrat")
      } footer: {
        Text("Beim Mindestbestand gibt es eine Warnung (Telegram). Die Nachkaufmenge landet bei „Knappe Zutaten auf die Einkaufsliste“ auf der Liste.")
      }

      Section {
        TextField("Kauf-Einheit, z. B. Würfel", text: $purchaseUnit)
        if !purchaseUnit.trimmed.isEmpty {
          LabeledContent("1 \(purchaseUnit.trimmed) =") {
            NumberField(title: "Menge", text: $purchaseUnitFactor, unit: unit).multilineTextAlignment(.trailing)
          }
        }
      } header: {
        Text("Kauf-Einheit (optional)")
      } footer: {
        Text("Wenn im Laden anders gezählt wird, z. B. Hefe: 1 Würfel = 42 g.")
      }

      if let entry, ingredientId != nil {
        Section {
          if entry.stock != nil {
            Button("Bestand entfernen", role: .destructive) { Task { await removeStock() } }
          }
          Button("Zutat ganz löschen", role: .destructive) { confirmDelete = true }
            .disabled((entry.usedInRecipes ?? 0) > 0)
        } footer: {
          if let used = entry.usedInRecipes, used > 0 {
            Text("Wird in \(used) Rezept\(used == 1 ? "" : "en") verwendet und kann nicht gelöscht werden.")
          }
        }
      }
    }
    .navigationTitle(ingredientId == nil ? "Neue Zutat" : name)
    .navigationBarTitleDisplayMode(.inline)
    .alertMessage($alert)
    .confirmationDialog("Zutat wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Löschen", role: .destructive) { Task { await deleteIngredient() } }
    }
    .sheet(isPresented: $showCamera) {
      CameraPicker { img in newImage = img }.ignoresSafeArea()
    }
    .onChange(of: photoItem) { _, item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) { newImage = img }
        photoItem = nil
      }
    }
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        if saving { ProgressView() } else {
          Button("Sichern") { Task { await save() } }
            .bold()
            .disabled(name.trimmed.isEmpty || unit.trimmed.isEmpty)
        }
      }
    }
    .task { await load() }
  }

  private func load() async {
    guard let ingredientId, entry == nil else { return }
    do {
      let e: PantryEntry = try await app.client.get("pantry/\(ingredientId)")
      entry = e
      name = e.name
      unit = e.unit
      dietType = e.dietType
      imagePath = e.imageUrl
      purchaseUnit = e.purchaseUnit ?? ""
      purchaseUnitFactor = Fmt.editable(e.purchaseUnitFactor)
      if let s = e.stock {
        quantity = Fmt.editable(s.quantity)
        minQuantity = Fmt.editable(s.minQuantity)
        purchaseQuantity = Fmt.editable(s.purchaseQuantity)
        unlimited = s.unlimited
        isPublic = s.isPublic
      }
    } catch { alert = .error(error) }
  }

  private func save() async {
    saving = true
    defer { saving = false }
    do {
      var image: String?? = nil
      if let newImage {
        image = .some(try await app.client.uploadImage(newImage))
      } else if imageRemoved {
        image = .some(nil)
      }
      let input = PantryInput(
        name: name.trimmed,
        unit: unit.trimmed,
        dietType: dietType,
        quantity: unlimited ? 0 : (Fmt.parse(quantity) ?? 0),
        minQuantity: unlimited ? nil : Fmt.parse(minQuantity),
        purchaseQuantity: unlimited ? nil : Fmt.parse(purchaseQuantity),
        purchaseUnit: purchaseUnit.nilIfEmpty,
        purchaseUnitFactor: purchaseUnit.nilIfEmpty == nil ? nil : Fmt.parse(purchaseUnitFactor),
        unlimited: unlimited,
        isPublic: isPublic,
        imageUrl: image
      )
      if let ingredientId {
        let _: PantryEntry = try await app.client.send("PUT", "pantry/\(ingredientId)", body: input)
      } else {
        let _: PantryEntry = try await app.client.send("POST", "pantry", body: input)
      }
      app.didChangeData()
      dismiss()
    } catch { alert = .error(error) }
  }

  private func removeStock() async {
    guard let ingredientId else { return }
    do {
      try await app.client.call("DELETE", "pantry/\(ingredientId)")
      app.didChangeData()
      dismiss()
    } catch { alert = .error(error) }
  }

  private func deleteIngredient() async {
    guard let ingredientId else { return }
    do {
      try await app.client.call("DELETE", "ingredients/\(ingredientId)")
      app.didChangeData()
      dismiss()
    } catch { alert = .error(error) }
  }
}
