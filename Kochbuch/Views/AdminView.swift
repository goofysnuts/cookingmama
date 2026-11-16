import SwiftUI

// MARK: - Nutzer

struct AdminUsersView: View {
  @Environment(AppModel.self) private var app
  @State private var users: [AdminUser] = []
  @State private var alert: AlertMessage?
  @State private var showNew = false
  @State private var passwordFor: AdminUser?
  @State private var newPassword = ""
  @State private var deleteTarget: AdminUser?

  var body: some View {
    List {
      let pending = users.filter { !$0.approved }
      if !pending.isEmpty {
        Section("Kontoanfragen") {
          ForEach(pending) { u in
            VStack(alignment: .leading, spacing: 6) {
              Text(u.username).font(.headline)
              Text("Angefragt \(Fmt.relative(u.createdAt))").font(.caption).foregroundStyle(.secondary)
              HStack {
                Button("Freigeben") { Task { await patch(u, ["approved": true]) } }.buttonStyle(.borderedProminent)
                Button("Ablehnen", role: .destructive) { deleteTarget = u }.buttonStyle(.bordered)
              }
            }
          }
        }
      }
      Section("Nutzer") {
        ForEach(users.filter(\.approved)) { u in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(u.username).font(.headline)
              if u.role == "admin" { Pill(text: "Admin", color: .purple) }
              Spacer()
              Text("\(u.recipeCount) Rezepte").font(.caption).foregroundStyle(.secondary)
            }
          }
          .contextMenu { menu(u) }
          .swipeActions {
            if !u.isSelf {
              Button("Löschen", role: .destructive) { deleteTarget = u }
            }
          }
        }
      }
    }
    .navigationTitle("Nutzer")
    .refreshable { await load() }
    .task { await load() }
    .alertMessage($alert)
    .toolbar {
      Button { showNew = true } label: { Image(systemName: "person.badge.plus") }
    }
    .sheet(isPresented: $showNew) { AdminNewUserView { Task { await load() } } }
    .alert("Neues Passwort", isPresented: Binding(get: { passwordFor != nil }, set: { if !$0 { passwordFor = nil } })) {
      SecureField("mind. 8 Zeichen", text: $newPassword)
      Button("Setzen") { if let u = passwordFor { Task { await setPassword(u) } } }
      Button("Abbrechen", role: .cancel) { passwordFor = nil }
    } message: {
      Text("Für \(passwordFor?.username ?? ""). Bestehende App-Anmeldungen werden abgemeldet.")
    }
    .confirmationDialog("\(deleteTarget?.username ?? "") wirklich löschen?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), titleVisibility: .visible) {
      Button("Löschen", role: .destructive) { if let u = deleteTarget { Task { await delete(u) } } }
    } message: {
      Text("Rezepte des Nutzers bleiben erhalten.")
    }
  }

  @ViewBuilder
  private func menu(_ u: AdminUser) -> some View {
    if u.role == "admin" {
      Button("Admin-Rolle entziehen") { Task { await patch(u, ["role": "member"]) } }
    } else {
      Button("Zum Admin machen") { Task { await patch(u, ["role": "admin"]) } }
    }
    Button("Passwort zurücksetzen") { newPassword = ""; passwordFor = u }
    if !u.isSelf {
      Button("Löschen", role: .destructive) { deleteTarget = u }
    }
  }

  private func load() async {
    do {
      let res: AdminUsersResponse = try await app.client.get("admin/users")
      users = res.users
    } catch { alert = .error(error) }
  }

  private func patch(_ u: AdminUser, _ values: [String: AdminValue]) async {
    do {
      try await app.client.call("PATCH", "admin/users/\(u.id)", body: values)
      await load()
    } catch { alert = .error(error) }
  }

  private func setPassword(_ u: AdminUser) async {
    struct Payload: Encodable { let newPassword: String }
    do {
      try await app.client.call("POST", "admin/users/\(u.id)/password", body: Payload(newPassword: newPassword))
      alert = AlertMessage(title: "Passwort gesetzt", message: nil)
    } catch { alert = .error(error) }
    passwordFor = nil
  }

  private func delete(_ u: AdminUser) async {
    do {
      try await app.client.call("DELETE", "admin/users/\(u.id)")
      await load()
    } catch { alert = .error(error) }
    deleteTarget = nil
  }
}

/// Bool oder String für PATCH-Bodies
enum AdminValue: Encodable, ExpressibleByBooleanLiteral, ExpressibleByStringLiteral {
  case bool(Bool), string(String)
  init(booleanLiteral value: Bool) { self = .bool(value) }
  init(stringLiteral value: String) { self = .string(value) }
  func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case let .bool(b): try c.encode(b)
    case let .string(s): try c.encode(s)
    }
  }
}

struct AdminNewUserView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.dismiss) private var dismiss
  let onCreated: () -> Void
  @State private var username = ""
  @State private var password = ""
  @State private var isAdmin = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      Form {
        TextField("Benutzername", text: $username).textInputAutocapitalization(.never).autocorrectionDisabled()
        SecureField("Passwort (mind. 8 Zeichen)", text: $password)
        Toggle("Admin", isOn: $isAdmin)
        if let error { Text(error).foregroundStyle(.red) }
      }
      .navigationTitle("Neuer Nutzer")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Anlegen") { Task { await create() } }.disabled(username.trimmed.count < 3 || password.count < 8)
        }
      }
    }
  }

  private func create() async {
    struct Payload: Encodable { let username: String; let password: String; let role: String }
    do {
      let _: IdResponse = try await app.client.send("POST", "admin/users", body: Payload(username: username.trimmed, password: password, role: isAdmin ? "admin" : "member"))
      onCreated()
      dismiss()
    } catch { self.error = error.localizedDescription }
  }
}

// MARK: - Backup

struct AdminBackupView: View {
  @Environment(AppModel.self) private var app
  @State private var alert: AlertMessage?
  @State private var backupURL: URL?
  @State private var loadingBackup = false

  var body: some View {
    Form {
      Section {
        if let backupURL {
          ShareLink(item: backupURL) { Label("Backup teilen / sichern", systemImage: "square.and.arrow.up") }
        }
        Button {
          Task { await downloadBackup() }
        } label: {
          HStack {
            Label("Datenbank-Backup erstellen", systemImage: "externaldrive")
            if loadingBackup { Spacer(); ProgressView() }
          }
        }
        .disabled(loadingBackup)
      } footer: {
        Text("Lädt eine Kopie der Datenbank herunter (ohne Fotos). Wiederherstellen geht über die Docker-Daten auf dem NAS.")
      }
    }
    .navigationTitle("Backup")
    .alertMessage($alert)
  }

  private func downloadBackup() async {
    loadingBackup = true
    defer { loadingBackup = false }
    do {
      let data = try await app.client.raw("admin/backup")
      let stamp = Date().formatted(.iso8601.year().month().day())
      let url = FileManager.default.temporaryDirectory.appendingPathComponent("kochbuch-backup-\(stamp).db")
      try data.write(to: url, options: .atomic)
      backupURL = url
    } catch { alert = .error(error) }
  }
}
