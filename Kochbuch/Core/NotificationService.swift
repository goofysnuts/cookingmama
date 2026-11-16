import BackgroundTasks
import Foundation
import UserNotifications

/// Holt neue Benachrichtigungen vom Server und zeigt sie als iPhone-Mitteilung.
///
/// Ohne kostenpflichtigen Apple-Developer-Account gibt es keinen echten Push (APNs).
/// Die App fragt deshalb selbst nach: beim Öffnen, jede Minute solange sie offen ist und im
/// Hintergrund über die iOS-Hintergrundaktualisierung (iOS entscheidet, wie oft – meist alle
/// 15 Minuten bis wenige Stunden). Stehzeiten plant die App zusätzlich lokal zur exakten Zeit.
@MainActor
enum NotificationService {
  static let refreshTaskId = "de.jannes.kochbuch.refresh"
  private static let lastSeenKey = "kochbuch.notifications.lastSeen"
  private static var running = false

  static func requestPermission() async -> Bool {
    let center = UNUserNotificationCenter.current()
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral: return true
    case .denied: return false
    default: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
  }

  static func isAuthorized() async -> Bool {
    let status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    return status == .authorized || status == .provisional || status == .ephemeral
  }

  /// Neue Benachrichtigungen abholen, als Mitteilung zeigen, Badge setzen.
  /// Rückgabe: Anzahl ungelesener Benachrichtigungen (nil bei Fehler).
  @discardableResult
  static func check(prefs: NotificationPrefs?) async -> Int? {
    let client = APIClient.shared
    guard client.isLoggedIn, !running else { return nil }
    running = true
    defer { running = false }

    guard let res: NotificationsResponse = try? await client.get("notifications") else { return nil }
    let defaults = UserDefaults.standard
    let newest = res.notifications.compactMap { Fmt.date($0.createdAt) }.max()

    if let lastSeen = defaults.object(forKey: lastSeenKey) as? Date {
      let fresh = res.notifications
        .filter { !$0.read }
        .filter { (Fmt.date($0.createdAt) ?? .distantPast) > lastSeen }
        .reversed()
      if await isAuthorized() {
        for n in fresh where shouldAlert(n, prefs: prefs) {
          await post(n)
        }
      }
    }
    // Beim allerersten Abruf nichts nachträglich melden, nur den Stand merken
    if let newest { defaults.set(newest, forKey: lastSeenKey) } else if defaults.object(forKey: lastSeenKey) == nil {
      defaults.set(Date(), forKey: lastSeenKey)
    }

    try? await UNUserNotificationCenter.current().setBadgeCount(res.unreadCount)
    return res.unreadCount
  }

  private static func shouldAlert(_ n: AppNotification, prefs: NotificationPrefs?) -> Bool {
    // Stehzeiten meldet die App bereits selbst per lokalem Timer
    if n.category == "restTimer", RestTimerNotifications.wasScheduledLocally(recipeId: n.recipeId) { return false }
    return prefs?.allows(n.category) ?? true
  }

  private static func post(_ n: AppNotification) async {
    let content = UNMutableNotificationContent()
    content.title = title(for: n.category)
    content.body = n.message
    content.sound = .default
    var info: [String: String] = ["notificationId": n.id]
    if let recipeId = n.recipeId { info["recipeId"] = recipeId }
    content.userInfo = info
    if n.category == "restTimer" { content.interruptionLevel = .timeSensitive }
    let request = UNNotificationRequest(identifier: "srv-\(n.id)", content: content, trigger: nil)
    try? await UNUserNotificationCenter.current().add(request)
  }

  private static func title(for category: String?) -> String {
    switch category {
    case "restTimer": return "Stehzeit vorbei"
    case "shoppingReminder": return "Einkaufsliste"
    case "comments": return "Neue Bewertung"
    case "admin": return "Kochbuch-Verwaltung"
    default: return "Kochbuch"
    }
  }

  // MARK: Hintergrundaktualisierung

  static func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(identifier: refreshTaskId)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  static func resetState() {
    UserDefaults.standard.removeObject(forKey: lastSeenKey)
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
  }
}
