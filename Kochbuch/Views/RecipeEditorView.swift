import PhotosUI
import SwiftUI

// MARK: - Bearbeitungsmodell

struct EditIngredient: Identifiable, Equatable {
  let id = UUID()
  var name = ""
  var quantity = ""
  var unit = ""
  var note = ""
  var dietType = "vegan"
  var alternativeName = ""
  var alternativeDietType = "vegan"
  var isPreDough = false
  var showDetails = false
}

struct EditStep: Identifiable, Equatable {
  let id = UUID()
  var kind = "step"
  var text = ""
  var location = ""
  var minutes = ""
  var isPreDough = false
  var isBakeStep = false
  /// Zutatenname -> Menge als Text
  var amounts: [String: String] = [:]
}

struct EditRestPlan: Identifiable, Equatable {
  let id = UUID()
  var location = ""
  var minMinutes = ""
  var maxMinutes = ""
}

enum EditImage: Identifiable, Equatable {
  case existing(String)
  case new(UUID, UIImage)

  var id: String {
    switch self {
    case let .existing(path): return path
    case let .new(id, _): return id.uuidString
    }
  }

  static func == (a: EditImage, b: EditImage) -> Bool { a.id == b.id }
}

// MARK: - Editor

struct RecipeEditorView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let recipe: RecipeDetail?

  @State private var title = ""
  @State private var description = ""
  @State private var recipeType = "kochen"
  @State private var mealTypes: Set<String> = []
  @State private var tags = ""
  @State private var prepMinutes = ""
  @State private var servings = ""
  @State private var bakeMinutes = ""
  @State private var bakeMinutesMax = ""
  @State private var bakeTemperature = ""
  @State private var bakeMode = ""
  @State private var bakeWithSteam = false
  @State private var kneadMinutes = ""
  @State private var preDoughType = ""
  @State private var calories = ""
  @State private var protein = ""
  @State private var carbs = ""
  @State private var fat = ""
  @State private var ingredients: [EditIngredient] = [EditIngredient()]
  @State private var steps: [EditStep] = [EditStep()]
  @State private var restPlans: [EditRestPlan] = []
  @State private var images: [EditImage] = []
  @State private var photoItems: [PhotosPickerItem] = []
  @State private var showCamera = false
  @State private var loaded = false
  @State private var saving = false
  @State private var alert: AlertMessage?

  private var isBaking: Bool { recipeType == "backen" }
  private var hasPreDough: Bool { isBaking && !preDoughType.trimmed.isEmpty }

  var body: some View {
    Form {
      basics
      imagesSection
      timesSection
      if isBaking { bakingSection }
      ingredientsSection
      stepsSection
      nutritionSection
    }
    .navigationTitle(recipe == nil ? "Neues Rezept" : "Rezept bearbeiten")
    .navigationBarTitleDisplayMode(.inline)
    .scrollDismissesKeyboard(.interactively)
    .alertMessage($alert)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        if saving {
          ProgressView()
        } else {
          Button("Sichern") { Task { await save() } }.bold()
        }
      }
      ToolbarItem(placement: .topBarLeading) { EditButton() }
    }
    .sheet(isPresented: $showCamera) {
      CameraPicker { img in images.append(.new(UUID(), img)) }.ignoresSafeArea()
    }
    .onChange(of: photoItems) { _, items in
      Task {
        for item in items {
          if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
            images.append(.new(UUID(), img))
          }
        }
        photoItems = []
      }
    }
    .onAppear {
      if !loaded { fill(); loaded = true }
    }
  }

  // MARK: Abschnitte

  private var basics: some View {
    Section("Rezept") {
      TextField("Titel", text: $title)
      TextField("Kurzbeschreibung (optional)", text: $description, axis: .vertical).lineLimit(1 ... 4)
      Picker("Art", selection: $recipeType) {
        Text("Kochrezept").tag("kochen")
        Text("Backrezept").tag("backen")
      }
      .pickerStyle(.segmented)
      VStack(alignment: .leading, spacing: 6) {
        Text("Passt zu").font(.caption).foregroundStyle(.secondary)
        FlowLayout(spacing: 6) {
          ForEach(Labels.mealTypes, id: \.self) { type in
            let on = mealTypes.contains(type)
            Button {
              if on { mealTypes.remove(type) } else { mealTypes.insert(type) }
            } label: {
              Text(Labels.mealType(type))
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(on ? Color.accentColor : Color.secondary.opacity(0.12), in: Capsule())
                .foregroundStyle(on ? Color.white : Color.primary)
            }
            .buttonStyle(.plain)
          }
        }
      }
      TextField("Tags, z. B. schnell familie", text: $tags)
        .textInputAutocapitalization(.never)
    }
  }

  private var imagesSection: some View {
    Section("Fotos") {
      if !images.isEmpty {
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(images) { img in
              ZStack(alignment: .topTrailing) {
                Group {
                  switch img {
                  case let .existing(path):
                    RemoteImage(url: app.client.mediaURL(path)) { Color.secondary.opacity(0.1) }
                  case let .new(_, ui):
                    Image(uiImage: ui).resizable().scaledToFill()
                  }
                }
                .frame(width: 90, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Button {
                  images.removeAll { $0.id == img.id }
                } label: {
                  Image(systemName: "xmark.circle.fill").foregroundStyle(Color.white, Color.black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .padding(3)
              }
            }
          }
        }
        Text("Das erste Foto ist das Titelbild.").font(.caption).foregroundStyle(.secondary)
      }
      PhotosPicker(selection: $photoItems, maxSelectionCount: 10, matching: .images) {
        Label("Aus Fotos wählen", systemImage: "photo.on.rectangle")
      }
      Button {
        showCamera = true
      } label: {
        Label("Foto aufnehmen", systemImage: "camera")
      }
    }
  }

  private var timesSection: some View {
    Section("Zeit & Portionen") {
      LabeledContent("Zubereitung") { NumberField(title: "Minuten", text: $prepMinutes, unit: "Min.").multilineTextAlignment(.trailing) }
      LabeledContent("Portionen") { NumberField(title: "Anzahl", text: $servings).multilineTextAlignment(.trailing) }
    }
  }

  private var bakingSection: some View {
    Section {
      LabeledContent("Temperatur") { NumberField(title: "°C", text: $bakeTemperature, unit: "°C").multilineTextAlignment(.trailing) }
      Picker("Modus", selection: $bakeMode) {
        Text("–").tag("")
        ForEach(Labels.bakeModes, id: \.self) { Text(Labels.bakeMode($0)).tag($0) }
      }
      LabeledContent("Backzeit") { NumberField(title: "Min.", text: $bakeMinutes, unit: "Min.").multilineTextAlignment(.trailing) }
      LabeledContent("bis (optional)") { NumberField(title: "Min.", text: $bakeMinutesMax, unit: "Min.").multilineTextAlignment(.trailing) }
      Toggle("Mit Dampf", isOn: $bakeWithSteam)
      LabeledContent("Knetzeit") { NumberField(title: "Min.", text: $kneadMinutes, unit: "Min.").multilineTextAlignment(.trailing) }
      TextField("Vorteig (z. B. Poolish, Sauerteig)", text: $preDoughType)

      ForEach($restPlans) { $plan in
        VStack(alignment: .leading) {
          TextField("Ort, z. B. Kühlschrank", text: $plan.location)
          HStack {
            NumberField(title: "min. Minuten", text: $plan.minMinutes)
            Text("–")
            NumberField(title: "max. Minuten", text: $plan.maxMinutes)
          }
        }
      }
      .onDelete { restPlans.remove(atOffsets: $0) }
      Button {
        restPlans.append(EditRestPlan())
      } label: {
        Label("Stehzeit planen", systemImage: "hourglass.badge.plus")
      }
    } header: {
      Text("Backen")
    } footer: {
      Text("Stehzeiten hier als Gesamtplanung je Ort (in Minuten). Wo sie in der Zubereitung liegen, legst du unten als Stehzeit-Schritt fest.")
    }
  }

  private var ingredientsSection: some View {
    Section {
      ForEach($ingredients) { $ing in
        VStack(alignment: .leading, spacing: 6) {
          IngredientNameField(title: "Zutat", text: $ing.name) { picked in
            ing.unit = picked.unit
            ing.dietType = picked.dietType
          }
          HStack {
            TextField("Menge", text: $ing.quantity).keyboardType(.decimalPad).frame(maxWidth: 90)
            let known = app.ingredient(named: ing.name)
            if let known {
              Text(known.unit).foregroundStyle(.secondary)
              Spacer()
            } else {
              TextField("Einheit", text: $ing.unit).textInputAutocapitalization(.never)
              Menu {
                ForEach(Labels.commonUnits, id: \.self) { u in Button(u) { ing.unit = u } }
              } label: {
                Image(systemName: "chevron.down.circle")
              }
            }
            Button {
              withAnimation { ing.showDetails.toggle() }
            } label: {
              Image(systemName: ing.showDetails ? "chevron.up" : "ellipsis.circle")
            }
            .buttonStyle(.borderless)
          }
          if ing.showDetails {
            TextField("Hinweis (z. B. gehackt)", text: $ing.note)
            if app.ingredient(named: ing.name) == nil {
              Picker("Einstufung", selection: $ing.dietType) {
                ForEach(Labels.dietTypes, id: \.self) { Text(Labels.diet($0)).tag($0) }
              }
            }
            IngredientNameField(title: "Alternative (optional, z. B. Margarine)", text: $ing.alternativeName)
            if !ing.alternativeName.trimmed.isEmpty, app.ingredient(named: ing.alternativeName) == nil {
              Picker("Einstufung Alternative", selection: $ing.alternativeDietType) {
                ForEach(Labels.dietTypes, id: \.self) { Text(Labels.diet($0)).tag($0) }
              }
            }
            if hasPreDough {
              Toggle("Gehört zum Vorteig", isOn: $ing.isPreDough)
            }
          }
        }
        .padding(.vertical, 2)
      }
      .onDelete { ingredients.remove(atOffsets: $0) }
      .onMove { ingredients.move(fromOffsets: $0, toOffset: $1) }
      Button {
        ingredients.append(EditIngredient())
      } label: {
        Label("Zutat hinzufügen", systemImage: "plus.circle")
      }
    } header: {
      Text("Zutaten")
    } footer: {
      Text("Mengen für die angegebene Portionenzahl. Bekannte Zutaten behalten ihre Einheit.")
    }
  }

  private var namedIngredients: [EditIngredient] {
    ingredients.filter { !$0.name.trimmed.isEmpty }
  }

  private var stepsSection: some View {
    Section {
      ForEach($steps) { $step in
        VStack(alignment: .leading, spacing: 6) {
          Picker("Art", selection: $step.kind) {
            Text("Schritt").tag("step")
            Text("Stehzeit").tag("rest")
          }
          .pickerStyle(.segmented)
          if step.kind == "rest" {
            TextField("Ort, z. B. Raumtemperatur", text: $step.location)
            NumberField(title: "Dauer in Minuten", text: $step.minutes, unit: "Min.")
          } else {
            TextField("Was ist zu tun?", text: $step.text, axis: .vertical).lineLimit(2 ... 8)
            if !namedIngredients.isEmpty {
              DisclosureGroup("Zutaten in diesem Schritt (\(step.amounts.values.filter { Fmt.parse($0) != nil }.count))") {
                ForEach(namedIngredients) { ing in
                  HStack {
                    Text(ing.name).lineLimit(1)
                    Spacer()
                    TextField("–", text: Binding(
                      get: { step.amounts[ing.name.trimmed] ?? "" },
                      set: { step.amounts[ing.name.trimmed] = $0 }
                    ))
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    Text(unitFor(ing)).foregroundStyle(.secondary).frame(minWidth: 30, alignment: .leading)
                    Button {
                      step.amounts[ing.name.trimmed] = ing.quantity
                    } label: {
                      Image(systemName: "arrow.down.to.line.compact")
                    }
                    .buttonStyle(.borderless)
                  }
                  .font(.callout)
                }
              }
              .font(.callout)
            }
            if isBaking {
              Toggle("Backschritt", isOn: $step.isBakeStep)
            }
          }
          if hasPreDough {
            Toggle("Gehört zum Vorteig", isOn: $step.isPreDough)
          }
        }
        .padding(.vertical, 2)
      }
      .onDelete { steps.remove(atOffsets: $0) }
      .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
      Button {
        steps.append(EditStep())
      } label: {
        Label("Schritt hinzufügen", systemImage: "plus.circle")
      }
      Button {
        steps.append(EditStep(kind: "rest"))
      } label: {
        Label("Stehzeit hinzufügen", systemImage: "hourglass")
      }
    } header: {
      Text("Zubereitung")
    } footer: {
      Text("Hakst du beim Kochen einen Schritt ab, auf den eine Stehzeit folgt, erinnert dich die App, wenn sie vorbei ist.")
    }
  }

  private var nutritionSection: some View {
    Section("Nährwerte pro Portion (optional)") {
      LabeledContent("Kalorien") { NumberField(title: "kcal", text: $calories, unit: "kcal").multilineTextAlignment(.trailing) }
      LabeledContent("Eiweiß") { NumberField(title: "g", text: $protein, unit: "g").multilineTextAlignment(.trailing) }
      LabeledContent("Kohlenhydrate") { NumberField(title: "g", text: $carbs, unit: "g").multilineTextAlignment(.trailing) }
      LabeledContent("Fett") { NumberField(title: "g", text: $fat, unit: "g").multilineTextAlignment(.trailing) }
    }
  }

  private func unitFor(_ ing: EditIngredient) -> String {
    app.ingredient(named: ing.name)?.unit ?? ing.unit
  }

  // MARK: Laden / Speichern

  private func fill() {
    guard let r = recipe else { return }
    title = r.title
    description = r.description ?? ""
    recipeType = r.recipeType
    mealTypes = Set(r.mealTypes)
    tags = r.tags.joined(separator: " ")
    prepMinutes = r.prepMinutes.map(String.init) ?? ""
    servings = r.servings.map(String.init) ?? ""
    bakeMinutes = r.bakeMinutes.map(String.init) ?? ""
    bakeMinutesMax = r.bakeMinutesMax.map(String.init) ?? ""
    bakeTemperature = r.bakeTemperature.map(String.init) ?? ""
    bakeMode = r.bakeMode ?? ""
    bakeWithSteam = r.bakeWithSteam
    kneadMinutes = r.kneadMinutes.map(String.init) ?? ""
    preDoughType = r.preDoughType ?? ""
    calories = Fmt.editable(r.nutritionPerServing?.caloriesKcal)
    protein = Fmt.editable(r.nutritionPerServing?.proteinG)
    carbs = Fmt.editable(r.nutritionPerServing?.carbsG)
    fat = Fmt.editable(r.nutritionPerServing?.fatG)
    ingredients = r.ingredients.map { ing in
      EditIngredient(
        name: ing.name, quantity: Fmt.editable(ing.quantity), unit: ing.unit, note: ing.note ?? "",
        dietType: ing.dietType, alternativeName: ing.alternative?.name ?? "",
        alternativeDietType: ing.alternative?.dietType ?? "vegan", isPreDough: ing.isPreDough
      )
    }
    if ingredients.isEmpty { ingredients = [EditIngredient()] }
    steps = r.steps.map { s in
      var amounts: [String: String] = [:]
      for i in s.ingredients ?? [] { amounts[i.name] = Fmt.editable(i.quantity) }
      return EditStep(
        kind: s.kind, text: s.text ?? "", location: s.location ?? "", minutes: s.minutes.map(String.init) ?? "",
        isPreDough: s.isPreDough ?? false, isBakeStep: s.isBakeStep ?? false, amounts: amounts
      )
    }
    if steps.isEmpty { steps = [EditStep()] }
    restPlans = r.restPlans.map { EditRestPlan(location: $0.location, minMinutes: String($0.minMinutes), maxMinutes: String($0.maxMinutes)) }
    images = r.images.map { .existing($0) }
  }

  private func int(_ s: String) -> Int? { Fmt.parse(s).map { Int($0.rounded()) } }

  private func validate() -> String? {
    if title.trimmed.isEmpty { return "Bitte einen Titel angeben." }
    if mealTypes.isEmpty { return "Bitte mindestens eine Mahlzeit auswählen." }
    let filled = namedIngredients
    if filled.isEmpty { return "Mindestens eine Zutat angeben." }
    for ing in filled {
      guard let q = Fmt.parse(ing.quantity), q > 0 else { return "Menge für „\(ing.name)“ fehlt." }
      if unitFor(ing).trimmed.isEmpty { return "Einheit für „\(ing.name)“ fehlt." }
    }
    let realSteps = steps.filter { $0.kind == "rest" ? (int($0.minutes) ?? 0) > 0 : !$0.text.trimmed.isEmpty }
    if realSteps.isEmpty { return "Mindestens einen Zubereitungsschritt angeben." }
    return nil
  }

  private func save() async {
    if let problem = validate() {
      alert = AlertMessage(title: "Noch nicht vollständig", message: problem)
      return
    }
    saving = true
    defer { saving = false }
    do {
      var imagePaths: [String] = []
      for img in images {
        switch img {
        case let .existing(path): imagePaths.append(path)
        case let .new(_, ui): imagePaths.append(try await app.client.uploadImage(ui))
        }
      }

      let names = Set(namedIngredients.map { $0.name.trimmed })
      let input = RecipeInput(
        title: title.trimmed,
        description: description.nilIfEmpty,
        recipeType: recipeType,
        mealTypes: Labels.mealTypes.filter { mealTypes.contains($0) },
        tags: tags.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init),
        prepMinutes: int(prepMinutes),
        servings: int(servings),
        bakeMinutes: isBaking ? int(bakeMinutes) : nil,
        bakeMinutesMax: isBaking ? int(bakeMinutesMax) : nil,
        bakeTemperature: isBaking ? int(bakeTemperature) : nil,
        bakeMode: isBaking ? bakeMode.nilIfEmpty : nil,
        bakeWithSteam: isBaking && bakeWithSteam,
        kneadMinutes: isBaking ? int(kneadMinutes) : nil,
        preDoughType: isBaking ? preDoughType.nilIfEmpty : nil,
        nutritionPerServing: Nutrition(caloriesKcal: Fmt.parse(calories), proteinG: Fmt.parse(protein), carbsG: Fmt.parse(carbs), fatG: Fmt.parse(fat)),
        ingredients: namedIngredients.map { ing in
          RecipeInput.Ingredient(
            name: ing.name.trimmed,
            quantity: Fmt.parse(ing.quantity) ?? 0,
            unit: unitFor(ing).trimmed,
            note: ing.note.nilIfEmpty,
            dietType: ing.dietType,
            alternativeName: ing.alternativeName.nilIfEmpty,
            alternativeDietType: ing.alternativeName.nilIfEmpty == nil ? nil : ing.alternativeDietType,
            isPreDough: hasPreDough && ing.isPreDough
          )
        },
        steps: steps.map { s in
          let stepIngredients: [StepIngredient] = s.amounts.compactMap { name, value in
            guard names.contains(name), let q = Fmt.parse(value), q > 0 else { return nil }
            let unit = namedIngredients.first(where: { $0.name.trimmed == name }).map(unitFor) ?? ""
            return StepIngredient(name: name, quantity: q, unit: unit)
          }
          return RecipeInput.Step(
            kind: s.kind,
            text: s.kind == "step" ? s.text.trimmed : nil,
            ingredients: s.kind == "step" ? stepIngredients : nil,
            location: s.kind == "rest" ? s.location.trimmed : nil,
            minutes: s.kind == "rest" ? int(s.minutes) : nil,
            isPreDough: hasPreDough && s.isPreDough,
            isBakeStep: isBaking && s.kind == "step" && s.isBakeStep
          )
        },
        restPlans: isBaking ? restPlans.compactMap { p in
          guard let min = int(p.minMinutes), min > 0, !p.location.trimmed.isEmpty else { return nil }
          return RestPlan(location: p.location.trimmed, minMinutes: min, maxMinutes: max(min, int(p.maxMinutes) ?? min))
        } : [],
        images: imagePaths
      )

      if let recipe {
        let _: RecipeDetail = try await app.client.send("PUT", "recipes/\(recipe.id)", body: input)
      } else {
        let _: RecipeDetail = try await app.client.send("POST", "recipes", body: input)
      }
      app.didChangeData()
      dismiss()
    } catch {
      alert = .error(error)
    }
  }
}
