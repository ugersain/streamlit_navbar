import Foundation

/// Drives the assistant UI on both Watch and iPhone.
@MainActor
final class AssistantViewModel: ObservableObject {
    enum Phase: Equatable { case idle, thinking, answered, failed }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var heard = ""
    @Published private(set) var reply: AssistantReply?
    @Published private(set) var history: [Turn] = []

    private let store: AppStore
    private let client: AssistantProviding

    init(store: AppStore, client: AssistantProviding = AppConfig.makeAssistant()) {
        self.store = store
        self.client = client
    }

    var pendingMeals: [FoodEstimate] {
        reply?.actions.filter { $0.type == "log_meal" }.flatMap { $0.items ?? [] } ?? []
    }
    var pendingTotalCalories: Int { pendingMeals.reduce(0) { $0 + $1.calories } }
    var hasMealToConfirm: Bool { !pendingMeals.isEmpty }
    var needsAttention: Bool { pendingMeals.contains { !$0.confident } }

    func submit(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        heard = trimmed
        reply = nil
        phase = .thinking

        let context = AssistantContext(
            calorieGoal: store.profile.calorieGoal,
            caloriesEaten: store.caloriesToday,
            proteinGoal: store.profile.proteinGoal,
            proteinEaten: store.proteinToday,
            diet: store.profile.diet,
            workoutToday: store.todaysWorkout?.title
        )
        do {
            let answer = try await client.ask(trimmed, context: context, history: Array(history.suffix(8)))
            reply = answer
            history.append(Turn(role: "user", text: trimmed))
            history.append(Turn(role: "assistant", text: answer.reply))
            // Reminders are safe to apply right away. Meals wait for the user's confirmation.
            let reminderOnly = AssistantReply(
                reply: answer.reply,
                actions: answer.actions.filter { $0.type == "add_reminder" },
                provider: answer.provider)
            store.apply(reminderOnly)
            phase = .answered
        } catch {
            phase = .failed
        }
    }

    /// Save the proposed meals to the diary.
    func confirmMeals() {
        guard let reply else { return }
        let mealsOnly = AssistantReply(
            reply: reply.reply,
            actions: reply.actions.filter { $0.type == "log_meal" },
            provider: reply.provider)
        store.apply(mealsOnly)
        dismiss()
    }

    func dismiss() {
        reply = nil
        heard = ""
        phase = .idle
    }
}
