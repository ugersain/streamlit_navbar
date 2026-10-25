import AuthenticationServices
import SwiftUI

/// Everything the onboarding questions collect, before it becomes a profile and plan.
@MainActor
final class OnboardingDraft: ObservableObject {
    @Published var name = ""
    @Published var sex: Sex = .unspecified
    @Published var age = 28
    @Published var heightCm = 175.0
    @Published var weightKg = 75.0
    @Published var targetKg = 72.0
    @Published var goal: GoalType = .lose
    @Published var activity: ActivityLevel = .light
    @Published var daysPerWeek = 4
    @Published var diet = "Vegetarian"
    @Published var allergies: Set<String> = []
    @Published var wakeMinutes = 6 * 60 + 30
    @Published var bedMinutes = 22 * 60 + 30
    @Published var workoutMinutes = 18 * 60 + 30
    @Published var wantsHealth = true
    @Published var wantsNotifications = true

    var plan: PlanResult {
        PlanBuilder.build(PlanInput(sex: sex, age: age, heightCm: heightCm, weightKg: weightKg,
                                    activity: activity, goal: goal))
    }
}

struct OnboardingFlow: View {
    @EnvironmentObject private var store: AppStore
    @EnvironmentObject private var health: HealthReader
    @StateObject private var draft = OnboardingDraft()
    @State private var step = 0

    private let lastQuestion = 7   // steps 2...7 show a progress bar

    var body: some View {
        ZStack {
            Pulse.background.ignoresSafeArea()
            switch step {
            case 0: welcome
            case 1: account
            case 2: about
            case 3: weight
            case 4: goal
            case 5: lifestyle
            case 6: food
            case 7: schedule
            case 8: permissions
            case 9: planStep
            default: watch
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    // MARK: Scaffold

    private func scaffold<Inner: View>(
        title: String, subtitle: String, buttonTitle: String = "Continue",
        buttonColor: Color = Pulse.fuel, canContinue: Bool = true,
        action: (() -> Void)? = nil, @ViewBuilder content: () -> Inner
    ) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Button { step -= 1 } label: {
                    Image(systemName: "chevron.left").font(.headline)
                        .frame(width: 44, height: 44).background(Pulse.surface, in: Circle())
                }
                .accessibilityLabel("Back")
                if (2...lastQuestion).contains(step) {
                    HStack(spacing: 4) {
                        ForEach(2...lastQuestion, id: \.self) { index in
                            Capsule().fill(index <= step ? Pulse.fuel : Pulse.surfaceRaised).frame(height: 5)
                        }
                    }
                    .accessibilityLabel("Step \(step - 1) of \(lastQuestion - 1)")
                    Text("\(step - 1)/\(lastQuestion - 1)").font(.caption.weight(.bold)).foregroundColor(Pulse.muted)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.system(.largeTitle, design: .rounded).weight(.heavy))
                Text(subtitle).font(.subheadline).foregroundColor(Pulse.muted)
            }
            ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
            PrimaryButton(title: buttonTitle, color: buttonColor, isEnabled: canContinue) {
                if let action { action() } else { step += 1 }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 16)
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.footnote.weight(.bold)).foregroundColor(Pulse.muted)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            HStack { Spacer(); PulseOrb(size: 140).padding(.vertical, 40); Spacer() }
            Text("Eat, train and live on your own rhythm")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
            Text("Track calories by voice, follow your gym plan, and get gentle reminders on your wrist, phone and laptop.")
                .foregroundColor(Pulse.muted)
            PrimaryButton(title: "Get started", color: Pulse.power) { step = 1 }.padding(.top, 8)
            Spacer().frame(height: 24)
        }
        .padding(.horizontal, 28)
    }

    private var account: some View {
        scaffold(title: "Create your account", subtitle: "One account for your Watch, phone and the web.",
                 buttonTitle: "Continue without an account", buttonColor: Pulse.surfaceRaised,
                 action: { step += 1 }) {
            VStack(spacing: 12) {
                SignInWithAppleButton(.signUp) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    // Backend verification of the Apple identity token is the next milestone.
                    // For now a successful sign-in just moves on and keeps data on this device.
                    if case .success(let auth) = result,
                       let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                       let given = credential.fullName?.givenName {
                        draft.name = given
                    }
                    if case .success = result { step += 1 }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                Text("Your data stays on this device until accounts launch. You can export or delete it any time.")
                    .font(.footnote).foregroundColor(Pulse.muted)
            }
        }
    }

    private var about: some View {
        scaffold(title: "Let's start with you", subtitle: "We use this to estimate your daily energy needs. It's optional and private.",
                 canContinue: !draft.name.trimmingCharacters(in: .whitespaces).isEmpty) {
            VStack(alignment: .leading, spacing: 18) {
                label("First name")
                TextField("Name", text: $draft.name)
                    .padding(16).background(Pulse.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .textContentType(.givenName)
                label("Sex used for calorie estimates")
                ChipFlow(items: Sex.allCases, label: { $0 == .unspecified ? "Prefer not to say" : $0.rawValue.capitalized },
                         isSelected: { $0 == draft.sex }) { draft.sex = $0 }
                Stepper("Age: \(draft.age)", value: $draft.age, in: 13...90)
                Stepper("Height: \(Int(draft.heightCm)) cm", value: $draft.heightCm, in: 120...220, step: 1)
            }
        }
    }

    private var weight: some View {
        scaffold(title: "Where are you now?", subtitle: "Set your current weight, then where you'd like to be.") {
            VStack(alignment: .leading, spacing: 18) {
                Card {
                    VStack(spacing: 6) {
                        label("CURRENT WEIGHT")
                        Text("\(draft.weightKg.formatted()) kg").font(.system(size: 52, weight: .heavy, design: .rounded))
                        Slider(value: $draft.weightKg, in: 35...200, step: 0.5).tint(Pulse.fuel)
                    }
                    .frame(maxWidth: .infinity)
                }
                Stepper("Target: \(draft.targetKg.formatted()) kg", value: $draft.targetKg, in: 35...200, step: 0.5)
                let diff = draft.weightKg - draft.targetKg
                if abs(diff) > 0.1 {
                    Text(diff > 0 ? "\(diff.formatted()) kg to lose. A steady pace is about 0.4 kg a week."
                                  : "\((-diff).formatted()) kg to gain. Slow and steady works best.")
                        .font(.footnote).foregroundColor(Pulse.muted)
                }
            }
        }
    }

    private var goal: some View {
        scaffold(title: "What's your main goal?", subtitle: "Pick what matters most right now. You can change it later.") {
            VStack(spacing: 10) {
                goalRow(.lose, "Lose weight", "A gentle calorie deficit with enough protein", Pulse.fuel)
                goalRow(.build, "Build muscle", "Progressive lifting, higher protein", Pulse.power)
                goalRow(.maintain, "Maintain my weight", "Balance what you eat and how you move", Pulse.move)
                goalRow(.healthier, "Get healthier", "Build consistent habits and routines", Pulse.routine)
                Text("General guidance, not medical advice. If you have a health condition, talk to a professional first.")
                    .font(.footnote).foregroundColor(Pulse.muted).padding(.top, 6)
            }
        }
    }

    private func goalRow(_ type: GoalType, _ title: String, _ detail: String, _ color: Color) -> some View {
        Button { draft.goal = type } label: {
            HStack(spacing: 14) {
                Circle().fill(color).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline.weight(.heavy)).foregroundColor(Pulse.text)
                    Text(detail).font(.footnote).foregroundColor(Pulse.muted)
                }
                Spacer()
                if draft.goal == type { Image(systemName: "checkmark.circle.fill").foregroundColor(color).font(.title2) }
            }
            .padding(16)
            .background(draft.goal == type ? color.opacity(0.16) : Pulse.surface,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(draft.goal == type ? color : Color.clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(draft.goal == type ? .isSelected : [])
    }

    private var lifestyle: some View {
        scaffold(title: "Tell us about your days", subtitle: "Outside of workouts, how active are you?") {
            VStack(alignment: .leading, spacing: 18) {
                ChipFlow(items: ActivityLevel.allCases, label: activityName, isSelected: { $0 == draft.activity }) { draft.activity = $0 }
                label("Workout days per week")
                HStack(spacing: 8) {
                    ForEach(2...6, id: \.self) { n in
                        Chip(title: "\(n)", selected: draft.daysPerWeek == n, color: Pulse.power) { draft.daysPerWeek = n }
                    }
                }
            }
        }
    }

    private func activityName(_ level: ActivityLevel) -> String {
        switch level {
        case .sitting: return "Mostly sitting"
        case .light: return "Lightly active"
        case .active: return "Active"
        case .veryActive: return "Very active"
        }
    }

    private var food: some View {
        scaffold(title: "How do you like to eat?", subtitle: "We'll suggest meals you'll actually enjoy.") {
            VStack(alignment: .leading, spacing: 18) {
                label("Diet type")
                ChipFlow(items: ["Vegetarian", "Non-vegetarian", "Eggetarian", "Vegan"], label: { $0 },
                         isSelected: { $0 == draft.diet }) { draft.diet = $0 }
                label("Allergies and foods to avoid")
                ChipFlow(items: ["Peanuts", "Dairy", "Gluten", "Shellfish", "Soy"], label: { $0 },
                         isSelected: { draft.allergies.contains($0) }, color: .red) { item in
                    if draft.allergies.contains(item) { draft.allergies.remove(item) } else { draft.allergies.insert(item) }
                }
            }
        }
    }

    private var schedule: some View {
        scaffold(title: "Shape your day", subtitle: "We'll time meals, reminders and workouts around your routine.") {
            VStack(alignment: .leading, spacing: 14) {
                timeRow("Wake up", $draft.wakeMinutes)
                timeRow("Bedtime", $draft.bedMinutes)
                timeRow("Usual workout time", $draft.workoutMinutes)
            }
        }
    }

    private func timeRow(_ title: String, _ minutes: Binding<Int>) -> some View {
        DatePicker(title, selection: Binding(
            get: { Calendar.current.date(bySettingHour: minutes.wrappedValue / 60, minute: minutes.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
            .padding(14).background(Pulse.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var permissions: some View {
        scaffold(title: "Make it work for you", subtitle: "Allow only what you want. You can change this later.",
                 buttonTitle: "Continue", buttonColor: Pulse.move, action: {
            Task {
                if draft.wantsHealth { await health.requestAccess() }
                if draft.wantsNotifications { _ = await Notifier.shared.requestAuthorization() }
                step += 1
            }
        }) {
            VStack(spacing: 10) {
                Toggle(isOn: $draft.wantsHealth) { permissionLabel("Apple Health", "Read activity and workouts, save finished workouts") }
                Toggle(isOn: $draft.wantsNotifications) { permissionLabel("Notifications", "Gentle reminders with quiet hours you control") }
                Text("Microphone and speech access are requested the first time you use voice.")
                    .font(.footnote).foregroundColor(Pulse.muted)
            }
            .tint(Pulse.power)
        }
    }

    private func permissionLabel(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline.weight(.heavy))
            Text(detail).font(.footnote).foregroundColor(Pulse.muted)
        }
    }

    private var planStep: some View {
        let plan = draft.plan
        return scaffold(title: "Your plan is ready", subtitle: "Here's where we'll start, \(draft.name).",
                        buttonTitle: "Looks good", buttonColor: Pulse.power, action: { finish() }) {
            VStack(spacing: 12) {
                Card(padding: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        label("DAILY CALORIES")
                        Text("\(plan.calories)").font(.system(size: 52, weight: .heavy, design: .rounded)).foregroundColor(Pulse.fuel)
                        Text(plan.weeklyChangeKg == 0 ? "Maintaining your weight"
                             : "About \(abs(plan.weeklyChangeKg).formatted()) kg per week \(plan.weeklyChangeKg < 0 ? "loss" : "gain")")
                            .font(.footnote).foregroundColor(Pulse.muted)
                        HStack {
                            macro("Protein", plan.proteinG, Pulse.power)
                            macro("Carbs", plan.carbsG, Pulse.fuel)
                            macro("Fat", plan.fatG, Pulse.fuel)
                        }
                    }
                }
                Card {
                    Text("\(draft.daysPerWeek)-day upper / lower split · \(draft.workoutMinutes.clockString)").font(.subheadline.weight(.semibold))
                }
                Card {
                    Text("Daily routine with water, stretching, meals and a wind-down. Reminders respect quiet hours.")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Estimates only. Your numbers adjust as you log meals and workouts.")
                    .font(.footnote).foregroundColor(Pulse.muted)
            }
        }
    }

    private func macro(_ name: String, _ grams: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).font(.caption).foregroundColor(Pulse.muted)
            Text("\(grams) g").font(.headline.weight(.heavy)).foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var watch: some View {
        scaffold(title: "Bring it to your wrist", subtitle: "Pulse for Apple Watch installs automatically when your Watch is paired.",
                 buttonTitle: "Go to Today", buttonColor: Pulse.power, action: {
            store.update { $0.profile.onboarded = true }
        }) {
            HStack { Spacer(); PulseOrb(size: 110).padding(.vertical, 30); Spacer() }
        }
    }

    // MARK: Finish

    private func finish() {
        let plan = draft.plan
        let weekdays = PlanBuilder.workoutWeekdays(daysPerWeek: draft.daysPerWeek)
        let templates = WorkoutDay.sample()
        let upper = templates[0].exercises, lower = templates[1].exercises
        let days = weekdays.enumerated().map { index, weekday in
            WorkoutDay(weekday: weekday, title: index % 2 == 0 ? "Upper body" : "Lower body",
                       startMinutes: draft.workoutMinutes,
                       exercises: (index % 2 == 0 ? upper : lower).map { exercise in
                           var copy = exercise
                           copy.id = UUID()
                           copy.sets = exercise.sets.map { ExerciseSet(weightKg: $0.weightKg, reps: $0.reps) }
                           return copy
                       })
        }
        let wake = draft.wakeMinutes
        let reminders = [
            Reminder(title: "Brush teeth and stretch", minutes: wake + 5),
            Reminder(title: "Breakfast", minutes: wake + 45),
            Reminder(title: "Drink water", minutes: 10 * 60 + 30),
            Reminder(title: "Lunch", minutes: 13 * 60),
            Reminder(title: "Drink water", minutes: 15 * 60 + 30),
            Reminder(title: "Dinner", minutes: 19 * 60 + 30),
            Reminder(title: "Wind down", minutes: max(draft.bedMinutes - 30, 0)),
        ]
        store.update { snap in
            snap.profile.name = draft.name
            snap.profile.calorieGoal = plan.calories
            snap.profile.proteinGoal = plan.proteinG
            snap.profile.carbsGoal = plan.carbsG
            snap.profile.fatGoal = plan.fatG
            snap.profile.diet = draft.diet
            snap.profile.quietStart = draft.bedMinutes
            snap.profile.quietEnd = wake - 30
            snap.plan = days
            snap.reminders = reminders
        }
        step += 1
    }
}
