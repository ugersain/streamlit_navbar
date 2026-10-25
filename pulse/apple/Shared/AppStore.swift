import Foundation
import SwiftUI

/// Single source of truth on each device. Persists to disk and syncs between iPhone and Watch.
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: Snapshot
    /// Called after every local change so the sync layer can send it to the other device.
    var onChange: ((Snapshot) -> Void)?

    private let fileURL: URL

    init(fileName: String = "pulse.json") {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent(fileName)
        if let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder.pulse.decode(Snapshot.self, from: data) {
            snapshot = saved
        } else {
            var fresh = Snapshot()
            fresh.plan = WorkoutDay.sample()
            fresh.reminders = Reminder.defaults()
            snapshot = fresh
        }
    }

    // MARK: - Reading

    var profile: Profile { snapshot.profile }

    var todaysMeals: [Meal] {
        snapshot.meals.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date < $1.date }
    }
    var caloriesToday: Int { todaysMeals.reduce(0) { $0 + $1.calories } }
    var proteinToday: Double { todaysMeals.reduce(0) { $0 + $1.protein } }
    var carbsToday: Double { todaysMeals.reduce(0) { $0 + $1.carbs } }
    var fatToday: Double { todaysMeals.reduce(0) { $0 + $1.fat } }
    var caloriesLeft: Int { profile.calorieGoal - caloriesToday }

    var todaysWorkout: WorkoutDay? {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return snapshot.plan.first { $0.weekday == weekday }
    }

    /// Next reminder that is not done today, preferring ones still ahead of the clock.
    var nextReminder: Reminder? {
        let now = Date()
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now)
        let minutesNow = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let pending = snapshot.reminders.filter { !$0.isDoneToday }.sorted { $0.minutes < $1.minutes }
        return pending.first { $0.minutes >= minutesNow } ?? pending.first
    }
    var remindersDoneToday: Int { snapshot.reminders.filter(\.isDoneToday).count }

    // MARK: - Writing

    func update(_ change: (inout Snapshot) -> Void) {
        change(&snapshot)
        snapshot.updatedAt = Date()
        persist()
        onChange?(snapshot)
    }

    func addMeals(_ meals: [Meal]) { update { $0.meals.append(contentsOf: meals) } }

    func deleteMeal(_ id: UUID) { update { $0.meals.removeAll { $0.id == id } } }

    func setSet(day: UUID, exercise: UUID, set: UUID, weightKg: Double? = nil, reps: Int? = nil, done: Bool? = nil) {
        update { snap in
            guard let d = snap.plan.firstIndex(where: { $0.id == day }),
                  let e = snap.plan[d].exercises.firstIndex(where: { $0.id == exercise }),
                  let s = snap.plan[d].exercises[e].sets.firstIndex(where: { $0.id == set }) else { return }
            if let weightKg { snap.plan[d].exercises[e].sets[s].weightKg = weightKg }
            if let reps { snap.plan[d].exercises[e].sets[s].reps = reps }
            if let done { snap.plan[d].exercises[e].sets[s].doneOn = done ? Date() : nil }
        }
    }

    func complete(_ reminder: Reminder) {
        update { snap in
            guard let i = snap.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
            if snap.reminders[i].oneOff {
                snap.reminders.remove(at: i)
            } else {
                snap.reminders[i].lastCompleted = Date()
                snap.reminders[i].snoozedUntil = nil
            }
        }
    }

    func snooze(_ reminder: Reminder, minutes: Int = 10) {
        update { snap in
            guard let i = snap.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
            snap.reminders[i].snoozedUntil = Date().addingTimeInterval(Double(minutes) * 60)
        }
        Notifier.shared.scheduleOnce(id: reminder.id.uuidString + ".snooze", title: reminder.title,
                                     afterMinutes: minutes, reminderID: reminder.id)
    }

    /// Apply what the assistant proposed, after the user confirmed.
    func apply(_ reply: AssistantReply) {
        for action in reply.actions {
            switch action.type {
            case "log_meal":
                addMeals((action.items ?? []).map { $0.asMeal() })
            case "add_reminder":
                guard let title = action.title else { continue }
                let minutes = action.minutesFromNow ?? 30
                let due = Date().addingTimeInterval(Double(minutes) * 60)
                let parts = Calendar.current.dateComponents([.hour, .minute], from: due)
                let reminder = Reminder(title: title, minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0), oneOff: true)
                update { $0.reminders.append(reminder) }
                Notifier.shared.scheduleOnce(id: reminder.id.uuidString, title: title, afterMinutes: minutes, reminderID: reminder.id)
            default:
                break
            }
        }
    }

    // MARK: - Sync

    /// Newer snapshot wins for settings and plans. Meals are merged by id so offline logs
    /// from either device are never lost. (Deleting a meal on one device while the other is
    /// offline can resurrect it; tombstones are the planned fix.)
    func merge(remote: Snapshot) {
        let remoteWins = remote.updatedAt > snapshot.updatedAt
        var merged = remoteWins ? remote : snapshot
        let known = Set(merged.meals.map(\.id))
        let other = remoteWins ? snapshot.meals : remote.meals
        merged.meals.append(contentsOf: other.filter { !known.contains($0.id) })
        merged.updatedAt = max(remote.updatedAt, snapshot.updatedAt)
        snapshot = merged
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder.pulse.encode(snapshot) else { return }
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtection])
    }
}
