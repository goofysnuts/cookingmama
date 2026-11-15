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

  /// Rezept, das per Tipp auf eine Mitteilung geöffnet werden soll
  var openRecipeId: String?

  /// Für den Notification-Delegate (Tipp auf Mitteilung)
  static weak var current: AppModel?

  /// Wird nach Änderungen erhöht, die andere Tabs betreffen (Vorrat, Rezepte) – Listen laden dann neu
  private(set) var revision = 0

  let client = APIClient.shared

  var isAdmin: Bool { me?.isAdmin ?? false }

  init() {
    isLoggedIn = APIClient.shared.isLoggedIn
    AppModel.current = self
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
    _ = await NotificationService.requestPermission()
    await checkNotifications()
  }

  /// Neue Benachrichtigungen abholen und als Mitteilung zeigen; aktualisiert den Zähler
  func checkNotifications() async {
    guard isLoggedIn else { return }
    if await NotificationService.check(prefs: me?.notificationPrefs) != nil {
      await refreshMe()
    }
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
    NotificationService.resetState()
    RestTimerNotifications.clear()
  }
}

/// Lokale Mitteilungen für Stehzeiten zur exakten Zeit (funktionieren ohne Apple-Push)
enum RestTimerNotifications {
  private static let key = "kochbuch.restTimers.local"

  static func schedule(recipeId: String, recipeTitle: String, label: String, at date: Date) async {
    guard await NotificationService.requestPermission() else { return }
    let seconds = date.timeIntervalSinceNow
    guard seconds > 1 else { return }
    let content = UNMutableNotificationContent()
    content.title = "Stehzeit vorbei!"
    content.body = "\(label) bei „\(recipeTitle)“ ist fertig – weiter geht's."
    content.sound = .default
    content.userInfo = ["recipeId": recipeId]
    content.interruptionLevel = .timeSensitive
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
    let request = UNNotificationRequest(identifier: "rest-\(recipeId)-\(Int(date.timeIntervalSince1970))", content: content, trigger: trigger)
    try? await UNUserNotificationCenter.current().add(request)

    var map = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    map[recipeId] = date.timeIntervalSince1970
    // Alte Einträge (älter als 2 Tage) aufräumen
    map = map.filter { $0.value > Date().timeIntervalSince1970 - 2 * 86400 }
    UserDefaults.standard.set(map, forKey: key)
  }

  /// Wurde für dieses Rezept in den letzten zwei Tagen ein lokaler Timer gestellt?
  static func wasScheduledLocally(recipeId: String?) -> Bool {
    guard let recipeId, let map = UserDefaults.standard.dictionary(forKey: key) as? [String: Double],
          let at = map[recipeId] else { return false }
    return at > Date().timeIntervalSince1970 - 2 * 86400
  }

  static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}
