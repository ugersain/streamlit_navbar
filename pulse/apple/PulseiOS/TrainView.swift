import SwiftUI

struct TrainView: View {
    @EnvironmentObject private var store: AppStore

    private let dayNames = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ScreenHeader(eyebrow: store.todaysWorkout.map { "\($0.exercises.count) exercises · \($0.startMinutes.clockString)" } ?? "Recover well",
                                 title: store.todaysWorkout?.title ?? "Rest day")
                    if let day = store.todaysWorkout {
                        ForEach(day.exercises) { exercise in
                            ExerciseCard(day: day, exercise: exercise)
                        }
                        Text("Do the workout from your Watch to track heart rate and save it to Apple Health.")
                            .font(.caption).foregroundColor(Pulse.muted).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Card {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your week").font(.headline.weight(.heavy))
                            ForEach(store.snapshot.plan.sorted { $0.weekday < $1.weekday }) { day in
                                HStack {
                                    Text(dayNames[day.weekday]).font(.subheadline.weight(.heavy)).frame(width: 44, alignment: .leading)
                                    Text(day.title).font(.subheadline)
                                    Spacer()
                                    Text(day.startMinutes.clockString).font(.footnote).foregroundColor(Pulse.muted)
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .screenBackground()
        }
    }
}

private struct ExerciseCard: View {
    @EnvironmentObject private var store: AppStore
    let day: WorkoutDay
    let exercise: Exercise

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(exercise.name).font(.headline.weight(.heavy))
                    Spacer()
                    Text("rest \(exercise.restSeconds)s").font(.caption).foregroundColor(Pulse.muted)
                }
                ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                    HStack(spacing: 12) {
                        Text("\(index + 1)").font(.subheadline.weight(.heavy)).frame(width: 24)
                        Stepper(value: Binding(
                            get: { set.weightKg },
                            set: { store.setSet(day: day.id, exercise: exercise.id, set: set.id, weightKg: $0) }
                        ), in: 0...400, step: 2.5) {
                            Text("\(set.weightKg.formatted()) kg × \(set.reps)").font(.subheadline)
                        }
                        Button {
                            store.setSet(day: day.id, exercise: exercise.id, set: set.id, done: !set.isDoneToday)
                        } label: {
                            Image(systemName: set.isDoneToday ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundColor(set.isDoneToday ? Pulse.power : Pulse.muted)
                                .frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(set.isDoneToday ? "Set \(index + 1) done" : "Mark set \(index + 1) done")
                    }
                }
            }
        }
    }
}
