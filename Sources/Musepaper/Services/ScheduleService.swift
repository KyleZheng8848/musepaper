import Foundation

@MainActor
final class ScheduleService {
    private var timers: [UUID: Timer] = [:]
    private var legacyTimer: Timer?

    nonisolated static func nextFireDate(hour: Int, from date: Date = Date(), calendar: Calendar = .current) -> Date {
        let clamped = min(max(hour, 0), 23)
        return calendar.nextDate(
            after: date,
            matching: DateComponents(hour: clamped, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(86400)
    }

    nonisolated static func nextFireCaption(hour: Int, from date: Date = Date(), locale: Locale = L10n.locale) -> String {
        caption(for: nextFireDate(hour: hour, from: date), locale: locale)
    }

    /// Continue a series from the last finished batch, not from a wall-clock hour.
    nonisolated static func nextFireDate(
        intervalHours: Int, lastProducedAt: Date?, from date: Date = Date()
    ) -> Date {
        nextFireDate(
            intervalSeconds: InspirationChannel.clampedInterval(intervalHours) * 3600,
            lastProducedAt: lastProducedAt, from: date
        )
    }

    nonisolated static func nextFireDate(
        intervalSeconds: Int, lastProducedAt: Date?, from date: Date = Date()
    ) -> Date {
        let interval = TimeInterval(InspirationChannel.clampedIntervalSeconds(intervalSeconds))
        if let last = lastProducedAt {
            let due = last.addingTimeInterval(interval)
            let slack = min(60, max(1, interval / 4))
            return due > date.addingTimeInterval(min(15, slack)) ? due : date.addingTimeInterval(slack)
        }
        return date.addingTimeInterval(interval)
    }

    nonisolated static func nextFireCaption(
        intervalHours: Int, lastProducedAt: Date?, from date: Date = Date(),
        locale: Locale = L10n.locale
    ) -> String {
        nextFireCaption(
            intervalSeconds: InspirationChannel.clampedInterval(intervalHours) * 3600,
            lastProducedAt: lastProducedAt, from: date, locale: locale
        )
    }

    nonisolated static func nextFireCaption(
        intervalSeconds: Int, lastProducedAt: Date?, from date: Date = Date(),
        locale: Locale = L10n.locale
    ) -> String {
        caption(
            for: nextFireDate(intervalSeconds: intervalSeconds, lastProducedAt: lastProducedAt, from: date),
            intervalSeconds: intervalSeconds, locale: locale
        )
    }

    private nonisolated static func caption(for fire: Date, intervalSeconds: Int = 3600, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(intervalSeconds % 60 == 0 ? "MMMd HHmm" : "MMMd HHmmss")
        return formatter.string(from: fire)
    }

    func configure(settings: AppSettings, action: @escaping @MainActor () -> Void) {
        legacyTimer?.invalidate()
        guard settings.scheduleEnabled else { return }
        let next = Self.nextFireDate(hour: settings.scheduleHour)
        legacyTimer = Timer(fire: next, interval: 86400, repeats: true) { _ in
            Task { @MainActor in action() }
        }
        RunLoop.main.add(legacyTimer!, forMode: .common)
    }

    func configure(tasks: [InspirationChannel], action: @escaping @MainActor (UUID) -> Void) {
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
        for task in tasks where task.resolvedScheduleEnabled {
            let seconds = task.resolvedScheduleIntervalSeconds
            let next = Self.nextFireDate(intervalSeconds: seconds, lastProducedAt: task.lastProducedAt)
            let taskID = task.id
            let timer = Timer(fire: next, interval: TimeInterval(seconds), repeats: true) { _ in
                Task { @MainActor in action(taskID) }
            }
            timers[taskID] = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    func stop() {
        legacyTimer?.invalidate()
        legacyTimer = nil
        timers.values.forEach { $0.invalidate() }
        timers.removeAll()
    }
}
