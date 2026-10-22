import UserNotifications
import Foundation

@MainActor
final class AlertManager {
    private let threshold = 0.9
    private let sustainedSamplesNeeded = 3
    private let cooldown: TimeInterval = 300

    private var cpuStreak = 0
    private var memStreak = 0
    private var lastCPUAlert: Date?
    private var lastMemAlert: Date?
    private let notificationsAvailable = Bundle.main.bundleIdentifier != nil

    init() {
        guard notificationsAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func check(cpuFraction: Double, memFraction: Double) {
        cpuStreak = cpuFraction >= threshold ? cpuStreak + 1 : 0
        memStreak = memFraction >= threshold ? memStreak + 1 : 0

        if cpuStreak >= sustainedSamplesNeeded {
            notify(title: "High CPU usage", body: "CPU has been above 90% for a while.", last: &lastCPUAlert)
        }
        if memStreak >= sustainedSamplesNeeded {
            notify(title: "High memory usage", body: "Memory has been above 90% for a while.", last: &lastMemAlert)
        }
    }

    private func notify(title: String, body: String, last: inout Date?) {
        guard notificationsAvailable else { return }
        let now = Date()
        if let last, now.timeIntervalSince(last) < cooldown { return }
        last = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
