import Foundation
import Observation
import UserNotifications

/// Globaler App-Zustand: Anmeldung, eigenes Konto, Zutaten-Stammdaten
@Observable
@MainActor
final class AppModel {
  private(set) var isLoggedIn: Bool
  private(set) var me: Me?
  private(set) var ingredients: [IngredientInfo] = []
  var loadError: String?

  /// Wird nach Änderungen erhöht, die andere Tabs betreffen (Vorrat, Rezepte) – Listen laden dann neu
  private(set) var revision = 0

  let client = APIClient.shared

  var isAdmin: Bool { me?.isAdmin ?? false }

  init() {
    isLoggedIn = APIClient.shared.isLoggedIn
    client.onUnauthorized = { [weak self] in
      self?.isLoggedIn = false
      self?.me = nil
    }
  }

  func didLogin(_ response: LoginResponse, server: String) async {
    client.store(server: server, token: response.token)
    me = response.user
    isLoggedIn = true
    await bootstrap()
  }

  func bootstrap() async {
    guard client.isLoggedIn else { return }
    do {
      me = try await client.get("me")
      loadError = nil
    } catch {
      loadError = error.localizedDescription
    }
    await reloadIngredients()
  }

  func refreshMe() async {
    if let fresh: Me = try? await client.get("me") { me = fresh }
  }

  func setMe(_ value: Me) { me = value }

  func reloadIngredients() async {
    if let list: IngredientListResponse = try? await client.get("ingredients") {
      ingredients = list.ingredients
    }
  }

  func ingredient(named name: String) -> IngredientInfo? {
    let key = name.trimmed.lowercased()
    return ingredients.first { $0.name.lowercased() == key }
  }

  /// Nach Änderungen (gekocht, Vorrat, Rezept gespeichert) aufrufen
  func didChangeData() {
    revision += 1
    Task { await reloadIngredients() }
  }

  func logout() async {
    try? await client.call("POST", "auth/logout")
    client.clearToken()
    me = nil
    isLoggedIn = false
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
  }
}

/// Lokale Benachrichtigungen für Stehzeiten (funktionieren ohne Apple-Push)
enum RestTimerNotifications {
  static func requestPermission() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional { return true }
    return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
  }

  static func schedule(recipeId: String, recipeTitle: String, label: String, at date: Date) async {
    guard await requestPermission() else { return }
    let seconds = date.timeIntervalSinceNow
    guard seconds > 1 else { return }
    let content = UNMutableNotificationContent()
    content.title = "Stehzeit vorbei!"
    content.body = "\(label) bei „\(recipeTitle)“ ist fertig – weiter geht's."
    content.sound = .default
    content.userInfo = ["recipeId": recipeId]
    if #available(iOS 15.0, *) { content.interruptionLevel = .timeSensitive }
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
    let request = UNNotificationRequest(identifier: "rest-\(recipeId)-\(Int(date.timeIntervalSince1970))", content: content, trigger: trigger)
    try? await UNUserNotificationCenter.current().add(request)
  }
}
