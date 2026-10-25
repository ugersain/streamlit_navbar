import SwiftUI
import WatchKit

struct WatchHomeView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthReader
    @Environment(\.metrics) private var m

    private var caloriesProgress: Double {
        Double(store.caloriesToday) / Double(max(store.profile.calorieGoal, 1))
    }
    private var proteinProgress: Double {
        store.proteinToday / Double(max(store.profile.proteinGoal, 1))
    }
    private var moveProgress: Double {
        health.activeCalories / Double(max(store.profile.activeGoal, 1))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: m.s(8)) {
                summary
                workoutCard
                routineRow
                actions
            }
            .padding(.horizontal, m.s(2))
        }
        .navigationTitle("Pulse")
        .navigationBarTitleDisplayMode(.inline)
        .task { await health.refresh() }
    }

    // MARK: Rings + numbers. Stacks vertically when the screen or text is too narrow.

    private var summary: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: m.s(10)) {
                ActivityRings(calories: caloriesProgress, protein: proteinProgress, move: moveProgress, size: m.s(80))
                stats
            }
            VStack(spacing: m.s(6)) {
                ActivityRings(calories: caloriesProgress, protein: proteinProgress, move: moveProgress, size: m.s(84))
                stats
            }
        }
    }

    private var stats: some View {
        VStack(alignment: .leading, spacing: m.s(4)) {
            stat(value: "\(store.caloriesToday)", suffix: "/ \(store.profile.calorieGoal)", color: Pulse.fuel)
            stat(value: "\(Int(store.proteinToday))", suffix: "/ \(store.profile.proteinGoal) g", color: Pulse.power)
            stat(value: "\(Int(health.activeCalories))", suffix: "move", color: Pulse.move)
        }
    }

    private func stat(value: String, suffix: String, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(.headline, design: .rounded).weight(.heavy))
                .foregroundColor(color)
            Text(suffix)
                .font(.caption2)
                .foregroundColor(Pulse.muted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .accessibilityElement(children: .combine)
    }

    // MARK: Workout and routine

    private var workoutCard: some View {
        NavigationLink {
            WorkoutView()
        } label: {
            WatchCard {
                HStack(spacing: m.s(8)) {
                    Image(systemName: "dumbbell.fill")
                        .font(.system(size: m.s(15), weight: .bold))
                        .foregroundColor(.black)
                        .frame(width: m.s(28), height: m.s(28))
                        .background(Pulse.move, in: RoundedRectangle(cornerRadius: m.s(9), style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.todaysWorkout?.title ?? "Rest day")
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                        Text(workoutSubtitle)
                            .font(.caption2)
                            .foregroundColor(Pulse.muted)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Today's workout: \(store.todaysWorkout?.title ?? "Rest day")")
    }

    private var workoutSubtitle: String {
        guard let day = store.todaysWorkout else { return "Recover well" }
        return "\(day.exercises.count) exercises · \(day.startMinutes.clockString)"
    }

    private var routineRow: some View {
        NavigationLink {
            WatchRemindersView()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill").foregroundColor(Pulse.routine).font(.caption2)
                if let next = store.nextReminder {
                    Text("Next: ").foregroundColor(Pulse.muted) + Text(next.title).fontWeight(.bold) + Text(" · \(next.minutes.clockString)").foregroundColor(Pulse.muted)
                } else {
                    Text("All reminders done").foregroundColor(Pulse.muted)
                }
            }
            .font(.caption2)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: Quick actions

    private var actions: some View {
        HStack(spacing: m.s(6)) {
            NavigationLink { WatchAssistantView() } label: { actionIcon("mic.fill", Pulse.fuel) }
                .buttonStyle(.plain)
                .accessibilityLabel("Log food by voice")
            NavigationLink { WorkoutView() } label: { actionIcon("play.fill", Pulse.power) }
                .buttonStyle(.plain)
                .accessibilityLabel("Start workout")
            Button {
                if let next = store.nextReminder {
                    store.complete(next)
                    WKInterfaceDevice.current().play(.success)
                }
            } label: { actionIcon("checkmark", Pulse.routine) }
                .buttonStyle(.plain)
                .accessibilityLabel("Mark next habit complete")
        }
    }

    private func actionIcon(_ systemName: String, _ color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: m.s(17), weight: .heavy))
            .foregroundColor(.black)
            .frame(maxWidth: .infinity, minHeight: max(m.s(40), 40))
            .background(color, in: Capsule())
    }
}

struct WatchRemindersView: View {
    @EnvironmentObject private var store: AppStore

    private var reminders: [Reminder] {
        store.snapshot.reminders.sorted { $0.minutes < $1.minutes }
    }

    var body: some View {
        List {
            ForEach(reminders) { reminder in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title)
                            .font(.system(.footnote, design: .rounded).weight(.bold))
                            .strikethrough(reminder.isDoneToday)
                        Text(reminder.minutes.clockString).font(.caption2).foregroundColor(Pulse.muted)
                    }
                    Spacer(minLength: 4)
                    if reminder.isDoneToday {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Pulse.routine)
                            .accessibilityLabel("Done")
                    } else {
                        Button {
                            store.complete(reminder)
                            WKInterfaceDevice.current().play(.success)
                        } label: { Image(systemName: "circle") }
                            .buttonStyle(.plain)
                            .foregroundColor(Pulse.routine)
                            .accessibilityLabel("Mark \(reminder.title) done")
                    }
                }
                .swipeActions {
                    if !reminder.isDoneToday {
                        Button("Snooze") { store.snooze(reminder) }.tint(Pulse.move)
                    }
                }
            }
        }
        .navigationTitle("Routine")
    }
}
