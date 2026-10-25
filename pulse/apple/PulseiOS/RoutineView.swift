import SwiftUI

struct RoutineView: View {
    @EnvironmentObject private var store: AppStore
    @State private var newTitle = ""
    @State private var newTime = Date()
    @State private var showAdd = false

    private var reminders: [Reminder] { store.snapshot.reminders.sorted { $0.minutes < $1.minutes } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    HStack(alignment: .bottom) {
                        ScreenHeader(eyebrow: Date().formatted(.dateTime.weekday(.wide).day().month(.wide)), title: "Your day")
                        Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title) }
                            .frame(width: 44, height: 44).accessibilityLabel("Add reminder")
                    }
                    ForEach(reminders) { reminder in
                        HStack(spacing: 12) {
                            Text(reminder.minutes.clockString)
                                .font(.footnote.weight(.semibold)).foregroundColor(Pulse.muted).frame(width: 74, alignment: .leading)
                            Text(reminder.title).font(.subheadline.weight(.semibold))
                                .strikethrough(reminder.isDoneToday).foregroundColor(reminder.isDoneToday ? Pulse.muted : Pulse.text)
                            Spacer()
                            Button { store.complete(reminder) } label: {
                                Image(systemName: reminder.isDoneToday ? "checkmark.circle.fill" : "circle")
                                    .font(.title2).foregroundColor(Pulse.routine).frame(width: 44, height: 44)
                            }
                            .disabled(reminder.isDoneToday)
                            .accessibilityLabel(reminder.isDoneToday ? "\(reminder.title) done" : "Mark \(reminder.title) done")
                        }
                        .padding(.horizontal, 14)
                        .background(Pulse.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contextMenu {
                            Button("Snooze 10 min") { store.snooze(reminder) }
                            Button("Delete", role: .destructive) {
                                store.update { $0.reminders.removeAll { $0.id == reminder.id } }
                            }
                        }
                    }
                    Text("Reminders stay quiet from \(store.profile.quietStart.clockString) to \(store.profile.quietEnd.clockString).")
                        .font(.caption).foregroundColor(Pulse.muted).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 120)
            }
            .screenBackground()
            .sheet(isPresented: $showAdd) {
                NavigationStack {
                    Form {
                        TextField("Reminder", text: $newTitle)
                        DatePicker("Time", selection: $newTime, displayedComponents: .hourAndMinute)
                    }
                    .navigationTitle("New reminder").navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showAdd = false } }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") {
                                let parts = Calendar.current.dateComponents([.hour, .minute], from: newTime)
                                let reminder = Reminder(title: newTitle, minutes: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
                                store.update { $0.reminders.append(reminder) }
                                newTitle = ""
                                showAdd = false
                            }
                            .disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
                .presentationDetents([.medium])
            }
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        List {
            Section("Targets") {
                Stepper("Calories: \(store.profile.calorieGoal)", value: bind(\.calorieGoal), in: 1000...5000, step: 50)
                Stepper("Protein: \(store.profile.proteinGoal) g", value: bind(\.proteinGoal), in: 30...300, step: 5)
                Stepper("Active energy: \(store.profile.activeGoal) kcal", value: bind(\.activeGoal), in: 100...2000, step: 50)
            }
            Section("Preferences") {
                Picker("Diet", selection: bind(\.diet)) {
                    ForEach(["Vegetarian", "Non-vegetarian", "Eggetarian", "Vegan"], id: \.self) { Text($0) }
                }
            }
            Section("Your data") {
                Text("Health data stays on your devices. Meals are only sent to the server when you ask the assistant to log them.")
                    .font(.footnote).foregroundColor(Pulse.muted)
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("Profile")
    }

    private func bind<T>(_ keyPath: WritableKeyPath<Profile, T>) -> Binding<T> {
        Binding(get: { store.profile[keyPath: keyPath] },
                set: { value in store.update { $0.profile[keyPath: keyPath] = value } })
    }
}
