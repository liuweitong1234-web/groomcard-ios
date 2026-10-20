import Foundation
import UserNotifications
import WebKit

/// Phone reminders for booked appointments. The GroomCard website sends the next week's bookings
/// (see syncPhoneReminders in app.js); this schedules a notification before each one, plus an
/// optional 7:00 morning summary. Everything is rescheduled each time, so edits and cancellations
/// are picked up automatically.
enum Reminders {
    private static let prefix = "groomcard."
    private static let maxReminders = 55   // iOS keeps at most 64 scheduled notifications per app

    private static let parser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    static func update(from body: [String: Any], webView: WKWebView) {
        let enabled = body["enabled"] as? Bool ?? true
        let morning = body["morningSummary"] as? Bool ?? true
        let minutes = body["minutesBefore"] as? Int ?? 30
        let items = body["items"] as? [[String: Any]] ?? []
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                // Ask the first time there's something to remind about.
                guard (enabled || morning) && !items.isEmpty else { return }
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    Reminders.report(granted ? "granted" : "denied", to: webView)
                    if granted {
                        Reminders.schedule(items: items, enabled: enabled, morning: morning, minutes: minutes)
                    }
                }
            case .denied:
                Reminders.report("denied", to: webView)
            default:
                Reminders.report("granted", to: webView)
                Reminders.schedule(items: items, enabled: enabled, morning: morning, minutes: minutes)
            }
        }
    }

    static func clearAll() {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ids = pending.map { $0.identifier }.filter { $0.hasPrefix(Reminders.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: ids)
        }
        center.removeAllDeliveredNotifications()
    }

    /// Tells the website whether notifications are allowed, so Settings can explain how to turn them on.
    static func reportPermission(to webView: WKWebView) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .denied:
                Reminders.report("denied", to: webView)
            case .notDetermined:
                Reminders.report("unknown", to: webView)
            default:
                Reminders.report("granted", to: webView)
            }
        }
    }

    private static func report(_ permission: String, to webView: WKWebView) {
        DispatchQueue.main.async {
            webView.evaluateJavaScript("window.groomcardOnNative && window.groomcardOnNative({permission: '\(permission)'})",
                                       completionHandler: nil)
        }
    }

    private static func schedule(items: [[String: Any]], enabled: Bool, morning: Bool, minutes: Int) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let old = pending.map { $0.identifier }.filter { $0.hasPrefix(Reminders.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)

            let now = Date()
            var scheduled = 0
            var byDay: [String: [[String: Any]]] = [:]

            for item in items {
                guard let start = item["start"] as? String, let date = Reminders.parser.date(from: start) else { continue }
                byDay[String(start.prefix(10)), default: []].append(item)
                guard enabled, scheduled < Reminders.maxReminders else { continue }
                let fireDate = date.addingTimeInterval(TimeInterval(-minutes * 60))
                guard fireDate > now else { continue }

                let pet = (item["pet_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "A pup"
                var details: [String] = []
                for key in ["service_name", "client_name", "address"] {
                    if let value = item[key] as? String, !value.isEmpty { details.append(value) }
                }
                if let flags = item["flags"] as? [String], !flags.isEmpty {
                    details.append("⚠️ " + flags.joined(separator: ", "))
                }

                let content = UNMutableNotificationContent()
                content.title = "🐾 \(pet) at \(start.suffix(5))"
                content.body = details.joined(separator: " · ")
                content.sound = .default
                content.userInfo = ["path": "/#/day/\(start.prefix(10))"]

                let idPart = (item["id"] as? Int).map { String($0) } ?? start
                Reminders.add(id: Reminders.prefix + "appointment." + idPart, content: content, at: fireDate, center: center)
                scheduled += 1
            }

            guard morning else { return }
            for day in byDay.keys.sorted().prefix(7) {
                let list = byDay[day] ?? []
                guard let at = Reminders.parser.date(from: "\(day) 07:00"), at > now, !list.isEmpty else { continue }
                let first = (list.first?["start"] as? String).map { String($0.suffix(5)) } ?? ""
                let content = UNMutableNotificationContent()
                content.title = list.count == 1 ? "1 pup booked today" : "\(list.count) pups booked today"
                content.body = "First one at \(first). Have a great grooming day! 🐾"
                content.sound = .default
                content.userInfo = ["path": "/#/day/\(day)"]
                Reminders.add(id: Reminders.prefix + "morning." + day, content: content, at: at, center: center)
            }
        }
    }

    private static func add(id: String, content: UNNotificationContent, at date: Date, center: UNUserNotificationCenter) {
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger), withCompletionHandler: nil)
    }
}
