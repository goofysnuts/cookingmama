import SwiftUI

struct LoginView: View {
  @Environment(AppModel.self) private var app

  enum Mode: String, CaseIterable, Identifiable {
    case login = "Anmelden", register = "Registrieren"
    var id: String { rawValue }
  }

  @State private var server = UserDefaults.standard.string(forKey: "kochbuch.server") ?? "http://192.168.30.145:5000"
  @State private var username = ""
  @State private var password = ""
  @State private var telegramChatId = ""
  @State private var mode: Mode = .login
  @State private var needsSetup = false
  @State private var busy = false
  @State private var error: String?
  @State private var info: String?

  var body: some View {
    NavigationStack {
      Form {
        Section {
          VStack(spacing: 8) {
            Image(systemName: "frying.pan")
              .font(.system(size: 54))
              .foregroundStyle(Color.accentColor)
            Text("Kochbuch").font(.largeTitle.bold())
            Text("Rezepte, Vorrat und Einkauf – von deinem NAS.")
              .font(.subheadline)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 8)
          .listRowBackground(Color.clear)
        }

        Section {
          TextField("http://NAS-IP:5000", text: $server)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          Button("Verbindung prüfen") { Task { await checkServer() } }
            .disabled(server.trimmed.isEmpty || busy)
        } header: {
          Text("Server")
        } footer: {
          Text("Adresse des Kochbuch-Containers, z. B. http://192.168.30.145:5000")
        }

        if needsSetup {
          Section {
            Text("Auf diesem Server gibt es noch kein Konto. Das erste Konto wird automatisch Admin.")
              .font(.callout)
          }
        } else {
          Picker("Modus", selection: $mode) {
            ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          .listRowBackground(Color.clear)
        }

        Section(needsSetup ? "Erstes Konto anlegen" : mode.rawValue) {
          TextField("Benutzername", text: $username)
            .textContentType(.username)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
          SecureField("Passwort", text: $password)
            .textContentType(mode == .register || needsSetup ? UITextContentType.newPassword : UITextContentType.password)
          if mode == .register, !needsSetup {
            TextField("Telegram-Chat-ID (optional)", text: $telegramChatId)
              .keyboardType(.numbersAndPunctuation)
          }
        }

        if let error {
          Section { Text(error).foregroundStyle(.red) }
        }
        if let info {
          Section { Text(info).foregroundStyle(.green) }
        }

        Section {
          Button {
            Task { await submit() }
          } label: {
            HStack {
              Spacer()
              if busy { ProgressView() } else {
                Text(needsSetup ? "Konto anlegen" : mode.rawValue).bold()
              }
              Spacer()
            }
          }
          .disabled(busy || username.trimmed.isEmpty || password.isEmpty || server.trimmed.isEmpty)
        } footer: {
          if mode == .register, !needsSetup {
            Text("Neue Konten muss ein Admin erst freigeben.")
          }
        }
      }
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  private var deviceName: String { UIDevice.current.name }

  private func checkServer() async {
    busy = true
    error = nil
    info = nil
    defer { busy = false }
    app.client.setServer(server)
    do {
      let status: StatusResponse = try await app.client.get("status")
      guard status.app == "kochbuch" else { error = "Unter dieser Adresse läuft kein Kochbuch."; return }
      needsSetup = status.needsSetup
      info = "Server erreichbar."
    } catch {
      self.error = error.localizedDescription
    }
  }

  private func submit() async {
    busy = true
    error = nil
    info = nil
    defer { busy = false }
    app.client.setServer(server)
    do {
      if needsSetup {
        let res: LoginResponse = try await app.client.send("POST", "auth/setup", body: Credentials(username: username.trimmed, password: password, deviceName: deviceName))
        await app.didLogin(res, server: server)
      } else if mode == .register {
        let res: MessageResponse = try await app.client.send("POST", "auth/register", body: Registration(username: username.trimmed, password: password, telegramChatId: telegramChatId.nilIfEmpty))
        info = res.message ?? "Konto angelegt. Ein Admin muss es noch freigeben."
        mode = .login
        password = ""
      } else {
        let res: LoginResponse = try await app.client.send("POST", "auth/login", body: Credentials(username: username.trimmed, password: password, deviceName: deviceName))
        await app.didLogin(res, server: server)
      }
    } catch {
      self.error = error.localizedDescription
    }
  }
}

private struct Credentials: Encodable {
  let username: String
  let password: String
  let deviceName: String
}

private struct Registration: Encodable {
  let username: String
  let password: String
  let telegramChatId: String?
}
