import Foundation

struct AssistantContext: Encodable {
    var calorieGoal: Int
    var caloriesEaten: Int
    var proteinGoal: Int
    var proteinEaten: Double
    var diet: String?
    var workoutToday: String?
}

struct Turn: Codable, Hashable {
    var role: String   // "user" or "assistant"
    var text: String
}

struct AssistantAction: Decodable, Hashable {
    var type: String                 // log_meal, add_reminder, none
    var items: [FoodEstimate]?
    var title: String?
    var minutesFromNow: Int?
    var needsConfirmation: Bool?
}

struct AssistantReply: Decodable, Hashable {
    var reply: String
    var actions: [AssistantAction]
    var provider: String
}

protocol AssistantProviding {
    func ask(_ text: String, context: AssistantContext, history: [Turn]) async throws -> AssistantReply
}

/// Talks to the Pulse backend. Model keys live on the server, never in the app.
struct RemoteAssistant: AssistantProviding {
    let baseURL: URL
    let token: String

    func ask(_ text: String, context: AssistantContext, history: [Turn]) async throws -> AssistantReply {
        struct Body: Encodable { let text: String; let context: AssistantContext; let history: [Turn] }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/assist"))
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(Body(text: text, context: context, history: history))

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AssistantReply.self, from: data)
    }
}

/// Works with no network: food logging via the bundled database, simple reminders.
struct OfflineAssistant: AssistantProviding {
    func ask(_ text: String, context: AssistantContext, history: [Turn]) async throws -> AssistantReply {
        let lowered = text.lowercased()
        if lowered.contains("remind") {
            let minutes = lowered.split(separator: " ").compactMap { Int($0) }.first ?? 30
            let raw = lowered.components(separatedBy: " to ").dropFirst().joined(separator: " to ")
            let title = raw.isEmpty ? "Reminder" : raw.prefix(1).uppercased() + raw.dropFirst()
            return AssistantReply(
                reply: "Okay, I'll remind you in \(minutes) min: \(title).",
                actions: [AssistantAction(type: "add_reminder", title: title, minutesFromNow: minutes)],
                provider: "offline")
        }
        let items = FoodDatabase.shared.parse(text)
        guard items.contains(where: { $0.confident }) else {
            return AssistantReply(reply: "I can log meals and set reminders. Try: log two rotis and a cup of dal.",
                                  actions: [AssistantAction(type: "none")], provider: "offline")
        }
        let kcal = items.reduce(0) { $0 + $1.calories }
        let protein = items.reduce(0) { $0 + $1.protein }
        let left = context.calorieGoal - context.caloriesEaten - kcal
        let unsure = items.contains { !$0.confident }
        var reply = "That's about \(kcal) kcal and \(Int(protein)) g protein. "
        reply += left >= 0 ? "\(left) kcal left today." : "\(-left) kcal over your goal."
        if unsure { reply += " Please check the items I wasn't sure about." }
        return AssistantReply(reply: reply,
                              actions: [AssistantAction(type: "log_meal", items: items, needsConfirmation: unsure)],
                              provider: "offline")
    }
}

/// Tries the server first, falls back to the offline assistant if it is unreachable.
struct ResilientAssistant: AssistantProviding {
    let remote: AssistantProviding?
    let offline: AssistantProviding = OfflineAssistant()

    func ask(_ text: String, context: AssistantContext, history: [Turn]) async throws -> AssistantReply {
        if let remote, let reply = try? await remote.ask(text, context: context, history: history) {
            return reply
        }
        return try await offline.ask(text, context: context, history: history)
    }
}

enum AppConfig {
    /// Server address comes from Info.plist (filled from Secrets.xcconfig, not committed).
    /// The token is the signed-in user's session token, kept in the Keychain.
    static func makeAssistant() -> AssistantProviding {
        guard let url = CloudClient.configuredURL, let token = Keychain.get("pulse.token") else {
            return ResilientAssistant(remote: nil)
        }
        return ResilientAssistant(remote: RemoteAssistant(baseURL: url, token: token))
    }
}
