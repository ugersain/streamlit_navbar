import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthReader
    var openAssistant: () -> Void
    @State private var showProfile = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let base = hour < 12 ? "Good morning" : (hour < 18 ? "Good afternoon" : "Good evening")
        return store.profile.name.isEmpty ? base : "\(base), \(store.profile.name)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(alignment: .top) {
                        ScreenHeader(eyebrow: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)), title: greeting)
                        Button { showProfile = true } label: {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 34)).foregroundColor(Pulse.muted)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel("Profile")
                    }
                    caloriesCard
                    workoutCard
                    upNext
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .screenBackground()
            .refreshable { await health.refresh() }
            .navigationDestination(isPresented: $showProfile) { ProfileView() }
        }
    }

    private var caloriesCard: some View {
        Card(padding: 20) {
            VStack(spacing: 16) {
                HStack(spacing: 20) {
                    ZStack {
                        ActivityRings(
                            calories: Double(store.caloriesToday) / Double(max(store.profile.calorieGoal, 1)),
                            protein: store.proteinToday / Double(max(store.profile.proteinGoal, 1)),
                            move: health.activeCalories / Double(max(store.profile.activeGoal, 1)),
                            size: 132)
                        VStack(spacing: 0) {
                            Text("\(max(store.caloriesLeft, 0))").font(.system(.title, design: .rounded).weight(.heavy))
                            Text("kcal left").font(.caption2).foregroundColor(Pulse.muted)
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        stat("EATEN", "\(store.caloriesToday)", "/ \(store.profile.calorieGoal)", Pulse.fuel)
                        stat("PROTEIN", "\(Int(store.proteinToday))", "/ \(store.profile.proteinGoal) g", Pulse.power)
                        stat("ACTIVE", "\(Int(health.activeCalories))", "kcal · Health", Pulse.move)
                    }
                }
                HStack(spacing: 10) {
                    macro("Carbs", store.carbsToday, store.profile.carbsGoal)
                    macro("Fat", store.fatToday, store.profile.fatGoal)
                }
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ suffix: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label).font(.caption2.weight(.semibold)).foregroundColor(Pulse.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value).font(.system(.title3, design: .rounded).weight(.heavy)).foregroundColor(color)
                Text(suffix).font(.caption).foregroundColor(Pulse.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func macro(_ name: String, _ value: Double, _ goal: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.caption.weight(.semibold)).foregroundColor(Pulse.muted)
            Text("\(Int(value))").font(.system(.headline, design: .rounded).weight(.heavy))
                + Text(" / \(goal) g").font(.caption).foregroundColor(Pulse.muted)
            ProgressView(value: min(value / Double(max(goal, 1)), 1)).tint(Pulse.fuel)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Pulse.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var workoutCard: some View {
        Card {
            HStack(spacing: 14) {
                Image(systemName: store.todaysWorkout == nil ? "bed.double.fill" : "dumbbell.fill")
                    .font(.system(size: 22, weight: .bold)).foregroundColor(.black)
                    .frame(width: 48, height: 48)
                    .background(Pulse.power, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.todaysWorkout?.title ?? "Rest day").font(.headline.weight(.heavy))
                    Text(store.todaysWorkout.map { "\($0.exercises.count) exercises · \($0.startMinutes.clockString)" } ?? "Recovery is part of the plan")
                        .font(.footnote).foregroundColor(Pulse.muted)
                }
                Spacer()
            }
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Up next").font(.headline.weight(.heavy))
                Spacer()
                Text("\(store.remindersDoneToday) of \(store.snapshot.reminders.count) done")
                    .font(.footnote.weight(.semibold)).foregroundColor(Pulse.routine)
            }
            let pending = store.snapshot.reminders.filter { !$0.isDoneToday }.sorted { $0.minutes < $1.minutes }.prefix(3)
            ForEach(Array(pending)) { reminder in
                HStack(spacing: 12) {
                    Button { store.complete(reminder) } label: {
                        Image(systemName: "circle").font(.title3).foregroundColor(Pulse.routine)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Mark \(reminder.title) done")
                    Text(reminder.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(reminder.minutes.clockString).font(.footnote).foregroundColor(Pulse.muted)
                }
                .padding(.horizontal, 6)
                .background(Pulse.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}
