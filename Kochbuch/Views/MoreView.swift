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
        NavigationLink { HouseholdsView() } label: { Label("Haushalte", systemImage: "house.and.flag") }
      }

      if app.isAdmin {
        Section("Admin") {
          NavigationLink { AdminUsersView() } label: { Label("Nutzer", systemImage: "person.2") }
          NavigationLink { AdminHouseholdsView() } label: { Label("Alle Haushalte", systemImage: "building.2") }
          NavigationLink { AdminSettingsView() } label: { Label("Telegram & Backup", systemImage: "gearshape.2") }
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
            if let invite = n.invite, invite.status == "pending" {
              HStack {
                Button("Annehmen") { Task { await respond(invite.id, accept: true) } }.buttonStyle(.borderedProminent)
                Button("Ablehnen") { Task { await respond(invite.id, accept: false) } }.buttonStyle(.bordered)
              }
              .padding(.leading, 16)
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

  private func respond(_ inviteId: String, accept: Bool) async {
    do {
      let _: HouseholdsResponse = try await app.client.send("POST", "invites/\(inviteId)/\(accept ? "accept" : "decline")")
      await load()
      await app.refreshMe()
      app.didChangeData()
    } catch { alert = .error(error) }
  }
}

// MARK: - Konto

struct AccountSettingsView: View {
  @Environment(AppModel.self) private var app
  @State private var diet = ""
  @State private var mealTimes: [String: Date] = [:]
  @State private var customMeal: Set<String> = []
  @State private var reminder: Int? = nil
  @State private var chatId = ""
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
        Picker("Telegram-Erinnerung", selection: $reminder) {
          ForEach(Labels.reminderIntervals, id: \.label) { Text($0.label).tag($0.hours) }
        }
      }

      Section {
        TextField(app.me?.telegramChatIdMasked ?? "Chat-ID", text: $chatId).keyboardType(.numbersAndPunctuation)
        if app.me?.telegramLinked == true {
          Button("Testnachricht senden") { Task { await telegramTest() } }
          Button("Verknüpfung entfernen", role: .destructive) { Task { await saveChatId("") } }
        }
        if !chatId.trimmed.isEmpty {
          Button("Chat-ID speichern") { Task { await saveChatId(chatId.trimmed) } }
        }
      } header: {
        Text("Telegram")
      } footer: {
        Text("Deine Chat-ID bekommst du z. B. von @userinfobot. Darüber kommen Vorrats-Warnungen, Stehzeit- und Einkaufserinnerungen.")
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

  private func saveChatId(_ value: String) async {
    struct Payload: Encodable { let telegramChatId: String }
    do {
      let me: Me = try await app.client.send("PATCH", "me", body: Payload(telegramChatId: value))
      app.setMe(me)
      chatId = ""
      alert = AlertMessage(title: value.isEmpty ? "Telegram entfernt" : "Chat-ID gespeichert", message: nil)
    } catch { alert = .error(error) }
  }

  private func telegramTest() async {
    do {
      try await app.client.call("POST", "me/telegram-test")
      alert = AlertMessage(title: "Gesendet", message: "Schau in Telegram nach der Testnachricht.")
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

// MARK: - Haushalte

struct HouseholdsView: View {
  @Environment(AppModel.self) private var app
  @State private var data: HouseholdsResponse?
  @State private var alert: AlertMessage?
  @State private var inviteTo: Household?
  @State private var inviteName = ""
  @State private var renameTarget: Household?
  @State private var newName = ""

  var body: some View {
    List {
      if let data {
        if !data.pendingInvites.isEmpty {
          Section("Einladungen") {
            ForEach(data.pendingInvites) { inv in
              VStack(alignment: .leading, spacing: 6) {
                Text("„\(inv.householdName)“\(inv.invitedBy.map { " von \($0)" } ?? "")")
                HStack {
                  Button("Annehmen") { Task { await respond(inv.id, true) } }.buttonStyle(.borderedProminent)
                  Button("Ablehnen") { Task { await respond(inv.id, false) } }.buttonStyle(.bordered)
                }
              }
            }
          }
        }
        ForEach(data.households) { h in
          Section {
            if h.isActive {
              Label("Aktiver Haushalt für den Vorrat", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
              Button("Als aktiven Haushalt wählen") { Task { await activate(h) } }
            }
            ForEach(h.members) { m in Label(m.username, systemImage: "person") }
            Button("Jemanden einladen") { inviteName = ""; inviteTo = h }
            Button("Umbenennen") { newName = h.name; renameTarget = h }
            if !h.isOwnHousehold {
              Button("Haushalt verlassen", role: .destructive) { Task { await leave(h) } }
            }
          } header: {
            Text(h.name + (h.isOwnHousehold ? " (eigener)" : ""))
          }
        }
        if app.me?.canJoinMultipleHouseholds == false {
          Text("Du kannst laut Admin-Einstellung keinen weiteren Haushalten beitreten.")
            .font(.footnote).foregroundStyle(.secondary)
        }
      } else {
        ProgressView().frame(maxWidth: .infinity)
      }
    }
    .navigationTitle("Haushalte")
    .refreshable { await load() }
    .task { await load() }
    .alertMessage($alert)
    .alert("Einladen", isPresented: Binding(get: { inviteTo != nil }, set: { if !$0 { inviteTo = nil } })) {
      TextField("Benutzername", text: $inviteName).textInputAutocapitalization(.never)
      Button("Einladen") { if let h = inviteTo { Task { await invite(h) } } }
      Button("Abbrechen", role: .cancel) { inviteTo = nil }
    }
    .alert("Umbenennen", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
      TextField("Name", text: $newName)
      Button("Sichern") { if let h = renameTarget { Task { await rename(h) } } }
      Button("Abbrechen", role: .cancel) { renameTarget = nil }
    }
  }

  private func load() async {
    do { data = try await app.client.get("households") } catch { alert = .error(error) }
  }

  private func activate(_ h: Household) async {
    struct Payload: Encodable { let householdId: String }
    do {
      data = try await app.client.send("PUT", "households/active", body: Payload(householdId: h.id))
      app.didChangeData()
    } catch { alert = .error(error) }
  }

  private func invite(_ h: Household) async {
    struct Payload: Encodable { let username: String }
    do {
      try await app.client.call("POST", "households/\(h.id)/invite", body: Payload(username: inviteName.trimmed))
      alert = AlertMessage(title: "Eingeladen", message: "\(inviteName.trimmed) sieht die Einladung in den Benachrichtigungen.")
    } catch { alert = .error(error) }
    inviteTo = nil
  }

  private func rename(_ h: Household) async {
    struct Payload: Encodable { let name: String }
    do { data = try await app.client.send("PATCH", "households/\(h.id)", body: Payload(name: newName.trimmed)) } catch { alert = .error(error) }
    renameTarget = nil
  }

  private func leave(_ h: Household) async {
    do {
      data = try await app.client.send("DELETE", "households/\(h.id)/membership")
      app.didChangeData()
    } catch { alert = .error(error) }
  }

  private func respond(_ id: String, _ accept: Bool) async {
    do {
      data = try await app.client.send("POST", "invites/\(id)/\(accept ? "accept" : "decline")")
      app.didChangeData()
    } catch { alert = .error(error) }
  }
}
