// Notifier.swift
// UNUserNotificationCenter behind the Notifying port. What to say and whether
// to say it was decided in the covered core.
// Excluded from coverage; audited by scripts/shim-audit.py.

import Foundation
import UserNotifications

/// Posts real user notifications.
final class Notifier: Notifying {

    private let center = UNUserNotificationCenter.current()

    init() {
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
