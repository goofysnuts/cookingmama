import SwiftUI

struct RecipeDetailView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let recipeId: String

  @State private var recipe: RecipeDetail?
  @State private var error: String?
  @State private var servings: Int = 1
  @State private var alert: AlertMessage?
  @State private var showShoppingSheet = false
  @State private var showCommentSheet = false
  @State private var showDeleteConfirm = false
  @State private var busy = false
  @State private var fullscreenImage: String?

  var body: some View {
    Group {
      if let recipe {
        content(recipe)
      } else if let error {
        ErrorBanner(message: error) { await load() }
      } else {
        ProgressView()
      }
    }
    .navigationTitle(recipe?.title ?? "")
    .navigationBarTitleDisplayMode(.inline)
    .task(id: app.revision) { await load() }
    .refreshable { await load() }
    .alertMessage($alert)
    .toolbar { toolbarItems }
    .sheet(isPresented: $showShoppingSheet) {
      if let recipe {
        ShoppingPickSheet(recipe: recipe, factor: scale(recipe), servings: servings) { message in
          alert = AlertMessage(title: "Einkaufsliste", message: message)
          app.didChangeData()
        }
      }
    }
    .sheet(isPresented: $showCommentSheet) {
      if let recipe {
        CommentSheet(recipe: recipe) { updated in self.recipe = updated }
      }
    }
    .fullScreenCover(item: Binding(get: { fullscreenImage.map { IdentifiedString(value: $0) } }, set: { fullscreenImage = $0?.value })) { item in
      ImageViewer(path: item.value)
    }
    .confirmationDialog("Rezept wirklich löschen?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
      Button("Löschen", role: .destructive) { Task { await deleteRecipe() } }
    }
  }

  // MARK: Inhalt

  @ViewBuilder
  private func content(_ r: RecipeDetail) -> some View {
    List {
      imagesSection(r)
      headerSection(r)
      bakeSection(r)
      ingredientsSection(r)
      stepsSection(r)
      nutritionSection(r)
      actionsSection(r)
      commentsSection(r)
    }
  }

  @ViewBuilder
  private func imagesSection(_ r: RecipeDetail) -> some View {
    if !r.images.isEmpty {
      Section {
        TabView {
          ForEach(r.images, id: \.self) { path in
            RemoteImage(url: app.client.mediaURL(path)) { Color.secondary.opacity(0.1) }
              .frame(maxWidth: .infinity)
              .frame(height: 240)
              .clipped()
              .contentShape(Rectangle())
              .onTapGesture { fullscreenImage = path }
          }
        }
        .tabViewStyle(.page(indexDisplayMode: r.images.count > 1 ? .automatic : .never))
        .frame(height: 240)
        .listRowInsets(EdgeInsets())
      }
    }
  }

  @ViewBuilder
  private func headerSection(_ r: RecipeDetail) -> some View {
    Section {
      VStack(alignment: .leading, spacing: 8) {
        Text(r.title).font(.title2.bold())
        if let d = r.description, !d.isEmpty {
          Text(d).foregroundStyle(.secondary)
        }
        FlowLayout(spacing: 6) {
          if let category = r.category {
            Pill(text: category.label, color: .brown)
          }
          Pill(text: r.isBaking ? "Backrezept" : "Kochrezept", systemImage: r.isBaking ? "birthday.cake" : "fork.knife")
          DietPill(diet: r.dietLabel)
          if let alt = r.dietLabelAlt, alt != r.dietLabel, alt != "keins" {
            Pill(text: "\(Labels.diet(alt)) mit Alternativen", color: .teal)
          }
          ForEach(r.mealTypes, id: \.self) { Pill(text: Labels.mealType($0), color: .orange) }
          ForEach(r.tags, id: \.self) { Pill(text: "#\($0)", color: .gray) }
        }
        HStack(spacing: 14) {
          if let p = r.prepMinutes { Label(Fmt.minutes(p), systemImage: "clock") }
          if r.rating.count > 0, let avg = r.rating.average {
            Label(String(format: "%.1f (%d)", avg, r.rating.count), systemImage: "star.fill")
          }
          if let n = r.timesCooked, n > 0 { Label("\(n)× gemacht", systemImage: "checkmark.seal") }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        Text("Von \(r.createdBy?.username ?? "gelöschtem Konto") · \(Fmt.day(r.createdAt))")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
  }

  @ViewBuilder
  private func bakeSection(_ r: RecipeDetail) -> some View {
    if r.isBaking, hasBakeInfo(r) {
      Section("Backen") {
        if let t = r.bakeTemperature { LabeledContent("Temperatur", value: "\(t) °C") }
        if let m = r.bakeMode { LabeledContent("Modus", value: Labels.bakeMode(m)) }
        if let b = r.bakeMinutes {
          LabeledContent("Backzeit", value: r.bakeMinutesMax.map { Fmt.range(b, $0) } ?? Fmt.minutes(b))
        }
        if r.bakeWithSteam { LabeledContent("Dampf", value: "Ja") }
        if let k = r.kneadMinutes { LabeledContent("Knetzeit", value: Fmt.minutes(k)) }
        if let v = r.preDoughType, !v.isEmpty { LabeledContent("Vorteig", value: v) }
        ForEach(r.restPlans, id: \.self) { p in
          LabeledContent("Stehzeit", value: Fmt.restPlan(p))
        }
      }
    }
  }

  @ViewBuilder
  private func ingredientsSection(_ r: RecipeDetail) -> some View {
    Section {
      if r.servings != nil {
        Stepper(value: $servings, in: 1 ... 100) {
          Text("\(servings) Portion\(servings == 1 ? "" : "en")")
        }
      }
      ForEach(r.ingredients) { ing in
        ingredientRow(ing, r)
      }
    } header: {
      Text("Zutaten")
    } footer: {
      if r.ingredients.contains(where: { $0.alternative != nil }) {
        Text("↔︎ = Alternative möglich (beim Kochen auswählbar)")
      }
    }
  }

  @ViewBuilder
  private func stepsSection(_ r: RecipeDetail) -> some View {
    Section {
      let realSteps = r.steps.filter { !$0.isRest }
      ForEach(r.steps) { step in
        stepRow(step, r, number: (realSteps.firstIndex(of: step) ?? 0) + 1)
      }
      if r.steps.contains(where: \.checked) {
        Button("Alle Haken entfernen") { Task { await resetSteps() } }
          .font(.footnote)
      }
    } header: {
      Text("Zubereitung")
    }
  }

  @ViewBuilder
  private func nutritionSection(_ r: RecipeDetail) -> some View {
    if let n = r.nutritionPerServing {
      Section("Nährwerte pro Portion") {
        if let v = n.caloriesKcal { LabeledContent("Kalorien", value: "\(Fmt.number(v)) kcal") }
        if let v = n.proteinG { LabeledContent("Eiweiß", value: "\(Fmt.number(v)) g") }
        if let v = n.carbsG { LabeledContent("Kohlenhydrate", value: "\(Fmt.number(v)) g") }
        if let v = n.fatG { LabeledContent("Fett", value: "\(Fmt.number(v)) g") }
      }
    }
  }

  @ViewBuilder
  private func actionsSection(_ r: RecipeDetail) -> some View {
    Section {
      Button {
        showShoppingSheet = true
      } label: {
        Label("Auf die Einkaufsliste", systemImage: "cart.badge.plus")
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

      Button {
        Task { await cook() }
      } label: {
        Label(r.isBaking ? "Heute gebacken" : "Heute gekocht", systemImage: "checkmark.circle")
      }
      .disabled(busy)
    }
  }

  @ViewBuilder
  private func commentsSection(_ r: RecipeDetail) -> some View {
    Section {
      let own = r.comments.first(where: \.isOwn)
      Button {
        showCommentSheet = true
      } label: {
        Label(own == nil ? "Bewerten / kommentieren" : "Eigene Bewertung ändern", systemImage: "star.bubble")
      }
      ForEach(r.comments) { c in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(c.user?.username ?? "gelöschtes Konto").font(.subheadline.bold())
            if let rating = c.rating {
              Text(String(repeating: "★", count: rating) + String(repeating: "☆", count: 5 - rating))
                .foregroundStyle(.yellow)
                .font(.caption)
            }
            Spacer()
            Text(Fmt.relative(c.createdAt)).font(.caption2).foregroundStyle(.tertiary)
          }
          if let t = c.text, !t.isEmpty { Text(t).font(.callout) }
        }
        .swipeActions {
          if c.canDelete {
            Button("Löschen", role: .destructive) { Task { await deleteComment(c) } }
          }
        }
      }
    } header: {
      Text("Bewertungen")
    }
  }


  private func hasBakeInfo(_ r: RecipeDetail) -> Bool {
    r.bakeTemperature != nil || r.bakeMinutes != nil || r.bakeMode != nil || !r.restPlans.isEmpty || r.kneadMinutes != nil || r.preDoughType != nil
  }

  private func bakeSummary(_ r: RecipeDetail) -> String? {
    var parts: [String] = []
    if let t = r.bakeTemperature { parts.append("\(t) °C") }
    if r.bakeMode != nil { parts.append(Labels.bakeMode(r.bakeMode)) }
    if let b = r.bakeMinutes {
      if let max = r.bakeMinutesMax { parts.append(Fmt.range(b, max)) } else { parts.append(Fmt.minutes(b)) }
    }
    if r.bakeWithSteam { parts.append("mit Dampf") }
    return parts.isEmpty ? nil : "🔥 " + parts.joined(separator: " · ")
  }

  private func scale(_ r: RecipeDetail) -> Double {
    guard let base = r.servings, base > 0 else { return 1 }
    return Double(servings) / Double(base)
  }

  @ViewBuilder
  private func ingredientRow(_ ing: RecipeIngredient, _ r: RecipeDetail) -> some View {
    let amount = ing.quantity * scale(r)
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(ing.name)
          if ing.isPreDough { Pill(text: "Vorteig", color: .brown) }
        }
        if let note = ing.note, !note.isEmpty {
          Text(note).font(.caption).foregroundStyle(.secondary)
        }
        if let alt = ing.alternative {
          Text("↔︎ \(alt.name)\(alt.dietType != ing.dietType ? " (\(Labels.diet(alt.dietType)))" : "")")
            .font(.caption)
            .foregroundStyle(.teal)
        }
      }
      Spacer()
      Text(Fmt.quantity(amount, ing.unit)).monospacedDigit().foregroundStyle(.secondary)
    }
  }

  @ViewBuilder
  private func stepRow(_ step: RecipeStepDTO, _ r: RecipeDetail, number: Int) -> some View {
    if step.isRest {
      HStack {
        Image(systemName: "hourglass").foregroundStyle(.purple)
        Text("Stehzeit \(Fmt.minutes(step.minutes ?? 0))\((step.location ?? "").isEmpty ? "" : " – \(step.location!)")")
          .font(.callout.weight(.medium))
          .foregroundStyle(.purple)
      }
    } else {
      Button {
        Task { await toggle(step, r) }
      } label: {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: step.checked ? "checkmark.circle.fill" : "\(min(number, 50)).circle")
            .font(.title3)
            .foregroundStyle(step.checked ? Color.green : Color.accentColor)
          VStack(alignment: .leading, spacing: 4) {
            if step.isPreDough == true { Pill(text: "Vorteig", color: .brown) }
            Text(step.text ?? "")
              .strikethrough(step.checked)
              .foregroundStyle(step.checked ? Color.secondary : Color.primary)
              .multilineTextAlignment(.leading)
            if let ings = step.ingredients, !ings.isEmpty {
              Text(ings.map { "\(Fmt.quantity($0.quantity * scale(r), $0.unit)) \($0.name)" }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if step.isBakeStep == true, let summary = bakeSummary(r) {
              Text(summary)
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
            }
          }
        }
      }
      .buttonStyle(.plain)
    }
  }

  @ToolbarContentBuilder
  private var toolbarItems: some ToolbarContent {
    ToolbarItemGroup(placement: .topBarTrailing) {
      if let r = recipe {
        Button {
          Task { await toggleFavorite(r) }
        } label: {
          Image(systemName: r.isFavorite ? "star.fill" : "star")
        }
        .tint(.yellow)
        if r.canEdit {
          Menu {
            NavigationLink {
              RecipeEditorView(recipe: r)
            } label: {
              Label("Bearbeiten", systemImage: "pencil")
            }
            Button(role: .destructive) {
              showDeleteConfirm = true
            } label: {
              Label("Löschen", systemImage: "trash")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
    }
  }

  // MARK: Aktionen

  private func load() async {
    do {
      let r: RecipeDetail = try await app.client.get("recipes/\(recipeId)")
      if recipe == nil || recipe?.servings != r.servings { servings = r.servings ?? 1 }
      recipe = r
      error = nil
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func toggle(_ step: RecipeStepDTO, _ r: RecipeDetail) async {
    struct Payload: Encodable { let checked: Bool }
    do {
      let res: StepToggleResponse = try await app.client.send("PUT", "recipes/\(r.id)/steps/\(step.index)", body: Payload(checked: !step.checked))
      if let timer = res.restTimer, let date = Fmt.date(timer.notifyAt), app.me?.notificationPrefs.restTimer ?? true {
        await RestTimerNotifications.schedule(recipeId: r.id, recipeTitle: r.title, label: timer.label, at: date)
        alert = AlertMessage(title: "Stehzeit läuft", message: "\(Fmt.minutes(timer.minutes)) (\(timer.label)). Du bekommst eine Benachrichtigung um \(date.formatted(date: .omitted, time: .shortened)).")
      }
      await load()
    } catch {
      alert = .error(error)
    }
  }

  private func resetSteps() async {
    do {
      try await app.client.call("DELETE", "recipes/\(recipeId)/steps")
      await load()
    } catch { alert = .error(error) }
  }

  private func toggleFavorite(_ r: RecipeDetail) async {
    do {
      let _: FavoriteResponse = try await app.client.send(r.isFavorite ? "DELETE" : "PUT", "recipes/\(r.id)/favorite")
      await load()
      app.didChangeData()
    } catch { alert = .error(error) }
  }

  private func cook() async {
    busy = true
    defer { busy = false }
    do {
      let res: MessageResponse = try await app.client.send("POST", "recipes/\(recipeId)/cook")
      alert = AlertMessage(title: "Guten Appetit!", message: res.message)
      app.didChangeData()
      await load()
    } catch { alert = .error(error) }
  }

  private func deleteComment(_ c: Comment) async {
    do {
      try await app.client.call("DELETE", "comments/\(c.id)")
      await load()
    } catch { alert = .error(error) }
  }

  private func deleteRecipe() async {
    do {
      try await app.client.call("DELETE", "recipes/\(recipeId)")
      app.didChangeData()
      dismiss()
    } catch { alert = .error(error) }
  }
}

struct IdentifiedString: Identifiable {
  let value: String
  var id: String { value }
}

// MARK: - Zutaten auf die Einkaufsliste

struct ShoppingPickSheet: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let recipe: RecipeDetail
  let factor: Double
  let servings: Int
  let onDone: (String) -> Void
  @State private var selected: Set<String> = []
  @State private var busy = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      List {
        Section {
          ForEach(recipe.ingredients) { ing in
            Button {
              if selected.contains(ing.id) { selected.remove(ing.id) } else { selected.insert(ing.id) }
            } label: {
              HStack {
                Image(systemName: selected.contains(ing.id) ? "checkmark.circle.fill" : "circle")
                  .foregroundStyle(selected.contains(ing.id) ? Color.accentColor : Color.secondary)
                Text(ing.name).foregroundStyle(Color.primary)
                Spacer()
                Text(Fmt.quantity(ing.quantity * factor, ing.unit)).foregroundStyle(.secondary).monospacedDigit()
              }
            }
          }
        } header: {
          HStack {
            Text(recipe.servings != nil ? "Für \(servings) Portion\(servings == 1 ? "" : "en")" : "Zutaten")
            Spacer()
            Button(selected.count == recipe.ingredients.count ? "Keine" : "Alle") {
              selected = selected.count == recipe.ingredients.count ? [] : Set(recipe.ingredients.map(\.id))
            }
            .font(.caption)
          }
        } footer: {
          Text("Hake an, was dir fehlt. Steht eine Zutat schon offen auf der Liste, wird die Menge dazugezählt.")
        }
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle("Auf die Einkaufsliste")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Hinzufügen (\(selected.count))") { Task { await save() } }
            .bold()
            .disabled(busy || selected.isEmpty)
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func save() async {
    struct Payload: Encodable { let factor: Double; let ingredientIds: [String] }
    struct Res: Decodable { let count: Int?; let added: Int? }
    busy = true
    defer { busy = false }
    do {
      let res: Res = try await app.client.send("POST", "recipes/\(recipe.id)/to-shopping-list", body: Payload(factor: factor, ingredientIds: Array(selected)))
      let count = res.count ?? 0
      let added = res.added ?? 0
      onDone(added == count ? "\(count) Zutat(en) eingetragen." : "\(count) Zutat(en) übernommen, davon \(count - added) zu bestehenden Einträgen dazugezählt.")
      dismiss()
    } catch {
      self.error = error.localizedDescription
    }
  }
}

// MARK: - Bewertung

struct CommentSheet: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let recipe: RecipeDetail
  let onSaved: (RecipeDetail) -> Void
  @State private var rating: Int = 0
  @State private var text = ""
  @State private var error: String?
  @State private var busy = false

  var body: some View {
    NavigationStack {
      Form {
        Section("Bewertung") {
          HStack {
            ForEach(1 ... 5, id: \.self) { i in
              Image(systemName: i <= rating ? "star.fill" : "star")
                .font(.title)
                .foregroundStyle(.yellow)
                .onTapGesture { rating = (rating == i ? 0 : i) }
            }
          }
          .frame(maxWidth: .infinity)
        }
        Section("Kommentar") {
          TextField("Wie war's?", text: $text, axis: .vertical).lineLimit(3 ... 8)
        }
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle("Bewerten")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Speichern") { Task { await save() } }
            .disabled(busy || (rating == 0 && text.trimmed.isEmpty))
        }
      }
      .onAppear {
        if let own = recipe.comments.first(where: \.isOwn) {
          rating = own.rating ?? 0
          text = own.text ?? ""
        }
      }
    }
    .presentationDetents([.medium, .large])
  }

  private func save() async {
    struct Payload: Encodable { let text: String?; let rating: Int? }
    busy = true
    defer { busy = false }
    do {
      let updated: RecipeDetail = try await app.client.send("PUT", "recipes/\(recipe.id)/comment", body: Payload(text: text.nilIfEmpty, rating: rating == 0 ? nil : rating))
      onSaved(updated)
      dismiss()
    } catch {
      self.error = error.localizedDescription
    }
  }
}

// MARK: - Vollbild-Bild

struct ImageViewer: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let path: String
  @State private var scale: CGFloat = 1

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Color.black.ignoresSafeArea()
      RemoteImage(url: app.client.mediaURL(path), contentMode: .fit) { ProgressView().tint(.white) }
        .scaleEffect(scale)
        .gesture(MagnificationGesture().onChanged { scale = max(1, $0) }.onEnded { _ in withAnimation { scale = 1 } })
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill").font(.largeTitle).foregroundStyle(Color.white.opacity(0.8))
      }
      .padding()
    }
  }
}

// MARK: - Umbrechendes Layout für Badges

struct FlowLayout: Layout {
  var spacing: CGFloat = 6

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let maxWidth = proposal.width ?? .infinity
    var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, width: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > 0, x + size.width > maxWidth {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
      width = max(width, x - spacing)
    }
    return CGSize(width: width, height: y + rowHeight)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
    for view in subviews {
      let size = view.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      x += size.width + spacing
      rowHeight = max(rowHeight, size.height)
    }
  }
}
