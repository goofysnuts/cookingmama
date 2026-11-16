import SwiftUI

struct MoreView: View {
  @Environment(AppModel.self) private var app
  @State private var confirmLogout = false

  var body: some View {
    List {
      if let me = app.me {
        Section {
          HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 44)).foregroundStyle(Color.accentColor)
            VStack(alignment: .leading) {
              Text(me.username).font(.title3.bold())
              Text(me.isAdmin ? "Admin" : "Mitglied").font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      }

      Section {
        NavigationLink { NotificationsView() } label: {
          HStack {
            Label("Benachrichtigungen", systemImage: "bell")
            Spacer()
            if let n = app.me?.unreadNotifications, n > 0 {
              Text("\(n)").font(.caption.bold()).padding(.horizontal, 7).padding(.vertical, 2)
                .background(Color.red, in: Capsule()).foregroundStyle(.white)
            }
          }
        }
        NavigationLink { FavoritesView() } label: { Label("Favoriten", systemImage: "star") }
        NavigationLink { AutoRecipesView() } label: { Label("Automatische Rezepte", systemImage: "sparkles") }
      }

      Section("Einstellungen") {
        NavigationLink { AccountSettingsView() } label: { Label("Konto & Ernährung", systemImage: "person.text.rectangle") }
        NavigationLink { NotificationSettingsView() } label: { Label("Mitteilungen", systemImage: "bell.badge") }
      }

      if app.isAdmin {
        Section("Admin") {
          NavigationLink { AdminUsersView() } label: { Label("Nutzer", systemImage: "person.2") }
          NavigationLink { AdminBackupView() } label: { Label("Backup", systemImage: "externaldrive") }
        }
      }

      Section {
        LabeledContent("Server", value: app.client.baseURL)
        Button("Abmelden", role: .destructive) { confirmLogout = true }
      } footer: {
        Text("Kochbuch \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")
      }
    }
    .navigationTitle("Mehr")
    .refreshable { await app.refreshMe() }
    .task { await app.refreshMe() }
    .confirmationDialog("Abmelden?", isPresented: $confirmLogout, titleVisibility: .visible) {
      Button("Abmelden", role: .destructive) { Task { await app.logout() } }
    }
  }
}

// MARK: - Favoriten

struct FavoritesView: View {
  @Environment(AppModel.self) private var app
  @State private var recipes: [RecipeSummary] = []
  @State private var loaded = false

  var body: some View {
    List {
      if loaded, recipes.isEmpty {
        ContentUnavailableView("Noch keine Favoriten", systemImage: "star", description: Text("Tippe in einem Rezept auf den Stern."))
      }
      ForEach(recipes) { r in
        NavigationLink { RecipeDetailView(recipeId: r.id) } label: { RecipeRow(recipe: r) }
      }
    }
    .listStyle(.plain)
    .navigationTitle("Favoriten")
    .task(id: app.revision) {
      if let res: RecipeListResponse = try? await app.client.get("recipes", query: ["favorites": "1", "diet": "alle"]) {
        recipes = res.recipes
      }
      loaded = true
    }
  }
}

// MARK: - Benachrichtigungen

struct NotificationsView: View {
  @Environment(AppModel.self) private var app
  @State private var data: NotificationsResponse?
  @State private var alert: AlertMessage?

  var body: some View {
    List {
      if let data {
        if data.notifications.isEmpty {
          ContentUnavailableView("Keine Benachrichtigungen", systemImage: "bell.slash")
        }
        ForEach(data.notifications) { n in
          VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
              Circle().fill(n.read ? Color.clear : Color.accentColor).frame(width: 8, height: 8).padding(.top, 6)
              VStack(alignment: .leading, spacing: 2) {
                Text(n.message).font(.callout)
                Text(Fmt.relative(n.createdAt)).font(.caption2).foregroundStyle(.tertiary)
              }
            }
            if let recipeId = n.recipeId {
              NavigationLink("Zum Rezept") { RecipeDetailView(recipeId: recipeId) }
                .font(.caption)
                .padding(.leading, 16)
                .simultaneousGesture(TapGesture().onEnded { Task { await markRead(n) } })
            }
          }
          .swipeActions {
            if !n.read {
              Button("Gelesen") { Task { await markRead(n) } }.tint(.blue)
            }
          }
        }
      } else {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
    .navigationTitle("Benachrichtigungen")
    .refreshable { await load() }
    .task { await load() }
    .alertMessage($alert)
    .toolbar {
      if (data?.unreadCount ?? 0) > 0 {
        Button("Alle gelesen") { Task { await markAll() } }
      }
    }
  }

  private func load() async {
    do {
      data = try await app.client.get("notifications")
    } catch { alert = .error(error) }
  }

  private func markRead(_ n: AppNotification) async {
    try? await app.client.call("POST", "notifications/\(n.id)/read")
    await load()
    await app.refreshMe()
  }

  private func markAll() async {
    try? await app.client.call("POST", "notifications/read-all")
    await load()
    await app.refreshMe()
  }

}

// MARK: - Konto

struct AccountSettingsView: View {
  @Environment(AppModel.self) private var app
  @State private var diet = ""
  @State private var mealTimes: [String: Date] = [:]
  @State private var customMeal: Set<String> = []
  @State private var reminder: Int? = nil
  @State private var currentPassword = ""
  @State private var newPassword = ""
  @State private var alert: AlertMessage?
  @State private var loaded = false

  var body: some View {
    Form {
      Section {
        Picker("Ernährung", selection: $diet) {
          Text("Keine Einschränkung").tag("")
          Text("Vegetarisch").tag("vegetarisch")
          Text("Vegan").tag("vegan")
        }
      } header: {
        Text("Ernährung")
      } footer: {
        Text("Filtert Vorschläge, Rezepte und Vorrat standardmäßig.")
      }

      Section {
        ForEach(Labels.configurableMealTypes, id: \.self) { type in
          VStack(alignment: .leading) {
            Toggle(isOn: Binding(
              get: { customMeal.contains(type) },
              set: { if $0 { customMeal.insert(type) } else { customMeal.remove(type) } }
            )) {
              Text(Labels.mealType(type))
            }
            if customMeal.contains(type) {
              DatePicker("Beginnt um", selection: Binding(
                get: { mealTimes[type] ?? Date() },
                set: { mealTimes[type] = $0 }
              ), displayedComponents: .hourAndMinute)
            } else {
              Text("Standard: ab \(defaultTime(type)) Uhr").font(.caption).foregroundStyle(.secondary)
            }
          }
        }
      } header: {
        Text("Essenszeiten")
      } footer: {
        Text("Eigene Startzeit je Mahlzeit – bestimmt, welche Vorschläge wann kommen.")
      }

      Section("Erinnerung an die Einkaufsliste") {
        Picker("Erinnern", selection: $reminder) {
          ForEach(Labels.reminderIntervals, id: \.label) { Text($0.label).tag($0.hours) }
        }
      }

      Section("Passwort ändern") {
        SecureField("Aktuelles Passwort", text: $currentPassword).textContentType(.password)
        SecureField("Neues Passwort (min. 8 Zeichen)", text: $newPassword).textContentType(.newPassword)
        Button("Passwort ändern") { Task { await changePassword() } }
          .disabled(currentPassword.isEmpty || newPassword.count < 8)
      }
    }
    .navigationTitle("Konto")
    .alertMessage($alert)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) {
        Button("Sichern") { Task { await save() } }.bold()
      }
    }
    .onAppear { if !loaded { fill(); loaded = true } }
  }

  private func defaultTime(_ type: String) -> String {
    let d = app.me?.defaultMealTimes
    switch type {
    case "fruehstueck": return d?.fruehstueck ?? ""
    case "mittag": return d?.mittag ?? ""
    case "snack": return d?.snack ?? ""
    default: return d?.abend ?? ""
    }
  }

  private static func parseTime(_ s: String?) -> Date? {
    guard let s else { return nil }
    let parts = s.split(separator: ":").compactMap { Int($0) }
    guard parts.count == 2 else { return nil }
    return Calendar.current.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: Date())
  }

  private static func formatTime(_ d: Date) -> String {
    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
    return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
  }

  private func fill() {
    guard let me = app.me else { return }
    diet = me.dietPreference ?? ""
    reminder = me.shoppingListReminderIntervalHours
    let own: [String: String?] = ["fruehstueck": me.mealTimes.fruehstueck, "mittag": me.mealTimes.mittag, "snack": me.mealTimes.snack, "abend": me.mealTimes.abend]
    for type in Labels.configurableMealTypes {
      if let value = own[type] ?? nil, let date = Self.parseTime(value) {
        customMeal.insert(type)
        mealTimes[type] = date
      } else {
        mealTimes[type] = Self.parseTime(defaultTime(type)) ?? Date()
      }
    }
  }

  private func save() async {
    struct Payload: Encodable {
      let dietPreference: String
      let mealTimes: [String: String]
      let shoppingListReminderIntervalHours: Int?
      enum CodingKeys: String, CodingKey { case dietPreference, mealTimes, shoppingListReminderIntervalHours }
      func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dietPreference, forKey: .dietPreference)
        try c.encode(mealTimes, forKey: .mealTimes)
        try c.encode(shoppingListReminderIntervalHours, forKey: .shoppingListReminderIntervalHours)
      }
    }
    var times: [String: String] = [:]
    for type in Labels.configurableMealTypes {
      times[type] = customMeal.contains(type) ? Self.formatTime(mealTimes[type] ?? Date()) : ""
    }
    do {
      let me: Me = try await app.client.send("PATCH", "me", body: Payload(dietPreference: diet, mealTimes: times, shoppingListReminderIntervalHours: reminder))
      app.setMe(me)
      app.didChangeData()
      alert = AlertMessage(title: "Gespeichert", message: nil)
    } catch { alert = .error(error) }
  }

  private func changePassword() async {
    struct Payload: Encodable { let currentPassword: String; let newPassword: String }
    do {
      try await app.client.call("POST", "me/password", body: Payload(currentPassword: currentPassword, newPassword: newPassword))
      currentPassword = ""; newPassword = ""
      alert = AlertMessage(title: "Passwort geändert", message: nil)
    } catch { alert = .error(error) }
  }
}

// MARK: - Mitteilungen

struct NotificationSettingsView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.openURL) private var openURL
  @State private var prefs = NotificationPrefs(comments: true, restTimer: true, shoppingReminder: true)
  @State private var authorized: Bool?
  @State private var loaded = false
  @State private var alert: AlertMessage?

  var body: some View {
    Form {
      Section {
        if authorized == false {
          Label("Mitteilungen sind für das Kochbuch ausgeschaltet.", systemImage: "bell.slash")
            .foregroundStyle(.orange)
          Button("In den iOS-Einstellungen erlauben") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          }
        } else if authorized == true {
          Label("Mitteilungen sind erlaubt.", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
      } footer: {
        Text("Die App schaut beim Öffnen, jede Minute solange sie offen ist und im Hintergrund nach Neuem. Wie oft der Hintergrundabruf läuft, entscheidet iOS (meist alle 15 Minuten bis einige Stunden) – dafür muss „Hintergrundaktualisierung“ für das Kochbuch an sein. Stehzeiten kommen immer pünktlich, die stellt die App selbst.")
      }

      Section("Mitteilung bei …") {
        Toggle("Stehzeit vorbei", isOn: $prefs.restTimer)
        Toggle("Erinnerung an die Einkaufsliste", isOn: $prefs.shoppingReminder)
        Toggle("Bewertungen deiner Rezepte", isOn: $prefs.comments)
      }
    }
    .navigationTitle("Mitteilungen")
    .alertMessage($alert)
    .task {
      if !loaded, let p = app.me?.notificationPrefs { prefs = p; loaded = true }
      authorized = await NotificationService.requestPermission()
    }
    .onChange(of: prefs) { old, new in
      guard loaded, old != new else { return }
      Task { await save(new) }
    }
  }

  private func save(_ value: NotificationPrefs) async {
    struct Payload: Encodable { let notificationPrefs: NotificationPrefs }
    do {
      let me: Me = try await app.client.send("PATCH", "me", body: Payload(notificationPrefs: value))
      app.setMe(me)
    } catch { alert = .error(error) }
  }
}
