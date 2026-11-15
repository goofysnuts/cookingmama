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
      if phase == .active, app.isLoggedIn {
        Task { await app.refreshMe() }
      }
    }
  }
}

/// Zeigt lokale Benachrichtigungen (Stehzeit) auch, wenn die App offen ist
final class NotificationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return true
  }

  func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
    [.banner, .sound, .list]
  }
}

struct RootView: View {
  @Environment(AppModel.self) private var app

  var body: some View {
    Group {
      if app.isLoggedIn {
        MainTabView()
      } else {
        LoginView()
      }
    }
    .animation(.default, value: app.isLoggedIn)
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
  }
}
