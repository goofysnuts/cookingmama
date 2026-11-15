import SwiftUI
import UserNotifications

@main
struct KochbuchApp: App {
  @State private var app = AppModel()
  @Environment(\.scenePhase) private var scenePhase
  @UIApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate

  init() {
    URLCache.shared = URLCache(memoryCapacity: 30 * 1024 * 1024, diskCapacity: 200 * 1024 * 1024)
  }

  var body: some Scene {
    WindowGroup {
      RootView()
        .environment(app)
        .task {
          if app.isLoggedIn { await app.bootstrap() }
        }
    }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        if app.isLoggedIn { Task { await app.checkNotifications() } }
      case .background:
        if app.isLoggedIn { NotificationService.scheduleBackgroundRefresh() }
      default:
        break
      }
    }
    .backgroundTask(.appRefresh(NotificationService.refreshTaskId)) {
      // Von iOS im Hintergrund gestartet: neue Benachrichtigungen abholen und nächsten Lauf anmelden
      await MainActor.run { NotificationService.scheduleBackgroundRefresh() }
      let prefs = await MainActor.run { AppModel.current?.me?.notificationPrefs }
      _ = await NotificationService.check(prefs: prefs)
    }
  }
}

/// Zeigt Mitteilungen auch bei geöffneter App und öffnet beim Tippen das passende Rezept
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return true
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .sound, .list]
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
    let info = response.notification.request.content.userInfo
    let recipeId = info["recipeId"] as? String
    let notificationId = info["notificationId"] as? String
    await MainActor.run {
      guard let app = AppModel.current else { return }
      if let recipeId { app.openRecipeId = recipeId }
      if let notificationId {
        Task {
          try? await app.client.call("POST", "notifications/\(notificationId)/read")
          await app.checkNotifications()
        }
      }
    }
  }
}

struct RootView: View {
  @Environment(AppModel.self) private var app
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    Group {
      if app.isLoggedIn {
        MainTabView()
      } else {
        LoginView()
      }
    }
    .animation(.default, value: app.isLoggedIn)
    .task(id: "\(app.isLoggedIn)-\(scenePhase == .active)") {
      // Solange die App offen ist: jede Minute nach neuen Benachrichtigungen schauen
      guard app.isLoggedIn, scenePhase == .active else { return }
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(60))
        if Task.isCancelled { break }
        await app.checkNotifications()
      }
    }
  }
}

enum AppTab: Hashable { case home, recipes, pantry, shopping, more }

struct MainTabView: View {
  @Environment(AppModel.self) private var app
  @State private var tab: AppTab = .home

  var body: some View {
    TabView(selection: $tab) {
      NavigationStack { DashboardView() }
        .tabItem { Label("Start", systemImage: "house") }
        .tag(AppTab.home)

      NavigationStack { RecipesView() }
        .tabItem { Label("Rezepte", systemImage: "book") }
        .tag(AppTab.recipes)

      NavigationStack { PantryView() }
        .tabItem { Label("Vorrat", systemImage: "refrigerator") }
        .tag(AppTab.pantry)

      NavigationStack { ShoppingListView() }
        .tabItem { Label("Einkauf", systemImage: "cart") }
        .tag(AppTab.shopping)

      NavigationStack { MoreView() }
        .tabItem { Label("Mehr", systemImage: "person.crop.circle") }
        .badge(app.me?.unreadNotifications ?? 0)
        .tag(AppTab.more)
    }
    .sheet(item: Binding(
      get: { app.openRecipeId.map { IdentifiedString(value: $0) } },
      set: { app.openRecipeId = $0?.value }
    )) { item in
      NavigationStack {
        RecipeDetailView(recipeId: item.value)
          .toolbar {
            ToolbarItem(placement: .cancellationAction) {
              Button("Schließen") { app.openRecipeId = nil }
            }
          }
      }
    }
  }
}
