import Foundation
import Security

/// Minimal Keychain wrapper for the session token.
enum Keychain {
    private static let service = "app.pulse.session"

    static func set(_ value: String?, for key: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: key]
        SecItemDelete(base as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var item = base
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: key,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct CloudError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Talks to the Pulse server with the signed-in user's session token.
struct CloudClient {
    let baseURL: URL
    let token: String?

    struct AuthResult: Decodable { let token: String; let userId: String; let email: String; let name: String }

    static var configuredURL: URL? {
        guard let text = Bundle.main.infoDictionary?["PULSE_API_URL"] as? String, !text.isEmpty else { return nil }
        return URL(string: text)
    }

    private func send(_ method: String, _ path: String, body: Data? = nil) async throws -> Data {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 20
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudError(message: "No response from the server.") }
        guard (200..<300).contains(http.statusCode) else {
            struct Problem: Decodable { let detail: String? }
            let detail = (try? JSONDecoder().decode(Problem.self, from: data))?.detail
            throw CloudError(message: detail ?? "Something went wrong (\(http.statusCode)).")
        }
        return data
    }

    func signup(email: String, password: String, name: String) async throws -> AuthResult {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password, "name": name])
        return try JSONDecoder().decode(AuthResult.self, from: try await send("POST", "v1/auth/signup", body: body))
    }

    func login(email: String, password: String) async throws -> AuthResult {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        return try JSONDecoder().decode(AuthResult.self, from: try await send("POST", "v1/auth/login", body: body))
    }

    func state() async throws -> Snapshot {
        try JSONDecoder.pulse.decode(Snapshot.self, from: try await send("GET", "v1/state"))
    }

    func push(_ snapshot: Snapshot) async throws -> Snapshot {
        let body = try JSONEncoder.pulse.encode(snapshot)
        return try JSONDecoder.pulse.decode(Snapshot.self, from: try await send("PUT", "v1/state", body: body))
    }

    func deleteAccount() async throws { _ = try await send("DELETE", "v1/account") }
}

/// Sign-in state and background sync with the server (iPhone only; the Watch syncs through the iPhone).
@MainActor
final class CloudAccount: ObservableObject {
    @Published private(set) var email: String? = UserDefaults.standard.string(forKey: "pulse.email")
    @Published private(set) var lastSyncFailed = false

    private let store: AppStore
    private var pushTask: Task<Void, Never>?
    private static let tokenKey = "pulse.token"

    init(store: AppStore) { self.store = store }

    var token: String? { Keychain.get(Self.tokenKey) }
    var isSignedIn: Bool { token != nil }
    private var client: CloudClient? {
        CloudClient.configuredURL.map { CloudClient(baseURL: $0, token: token) }
    }
    var serverConfigured: Bool { CloudClient.configuredURL != nil }

    /// Create an account. Existing local data (for example from onboarding) is uploaded.
    func signup(email: String, password: String, name: String) async throws {
        guard let client else { throw CloudError(message: "This build has no server address. Set PULSE_API_URL.") }
        let result = try await client.signup(email: email, password: password, name: name)
        remember(result)
        await pushNow()
    }

    /// Log in. If the account already has a profile, it replaces local data.
    func login(email: String, password: String) async throws {
        guard let client else { throw CloudError(message: "This build has no server address. Set PULSE_API_URL.") }
        let result = try await client.login(email: email, password: password)
        remember(result)
        let remote = try await CloudClient(baseURL: client.baseURL, token: result.token).state()
        if remote.profile.onboarded { store.adopt(remote) } else { await pushNow() }
    }

    func logout() { Keychain.set(nil, for: Self.tokenKey); UserDefaults.standard.removeObject(forKey: "pulse.email"); email = nil }

    func deleteRemoteAccount() async throws {
        try await client?.deleteAccount()
        logout()
    }

    private func remember(_ result: CloudClient.AuthResult) {
        Keychain.set(result.token, for: Self.tokenKey)
        UserDefaults.standard.set(result.email, forKey: "pulse.email")
        email = result.email
    }

    /// Debounced upload after local changes.
    func schedulePush() {
        guard isSignedIn else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.pushNow()
        }
    }

    func pushNow() async {
        guard let client, isSignedIn else { return }
        let sent = store.snapshot
        do {
            let merged = try await client.push(sent)
            store.acknowledgeSync(of: sent.deletedIds)
            store.merge(remote: merged)
            lastSyncFailed = false
        } catch {
            lastSyncFailed = true
        }
    }

    func pull() async {
        guard let client, isSignedIn else { return }
        if let remote = try? await client.state() {
            store.merge(remote: remote)
            lastSyncFailed = false
        } else {
            lastSyncFailed = true
        }
    }

    /// Token for the assistant requests.
    func authorizedAssistant() -> AssistantProviding {
        guard let client, let token else { return ResilientAssistant(remote: nil) }
        return ResilientAssistant(remote: RemoteAssistant(baseURL: client.baseURL, token: token))
    }
}
