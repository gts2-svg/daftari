import SwiftUI
import SwiftData
import UserNotifications

@main
struct DaftariApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .daftariEnvironment()
        }
        .modelContainer(Store.container)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationFactory.registerCategories()
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let action = response.actionIdentifier
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let uid = content.userInfo["uid"] as? String
        let text = (response as? UNTextInputNotificationResponse)?.userText
        Task { @MainActor in
            NotificationRouter.handle(action: action, category: category, uid: uid, text: text)
            completionHandler()
        }
    }
}

struct DaftariEnvironment: ViewModifier {
    @AppStorage(Prefs.Key.hijriPrimary) private var hijriPrimary = true

    func body(content: Content) -> some View {
        content
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, DF.locale)
            .environment(\.calendar, hijriPrimary ? DF.hijri : DF.greg)
            .preferredColorScheme(.light)
            .tint(T.accent)
    }
}

extension View {
    func daftariEnvironment() -> some View { modifier(DaftariEnvironment()) }
}
