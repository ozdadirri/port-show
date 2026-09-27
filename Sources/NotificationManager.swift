import Foundation
import UserNotifications

final class NotificationManager {
    static let shared = NotificationManager()

    private var authorized = false

    func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            self.authorized = granted
        }
    }

    func notifyPortWentUp(port: Int, label: String) {
        send(title: "\(label) is up", body: "Port \(port) is now listening.")
    }

    func notifyPortWentDown(port: Int, label: String) {
        send(title: "\(label) went down", body: "Port \(port) is no longer listening.")
    }

    private func send(title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
}
