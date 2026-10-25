import XCTest
@testable import Pulse

final class FoodDatabaseTests: XCTestCase {
    func testParsesTheSpecExample() {
        let items = FoodDatabase.shared.parse("Log two rotis, one bowl of dal, and a cup of curd")
        XCTAssertEqual(items.map(\.name), ["roti", "dal", "curd"])
        XCTAssertEqual(items.map(\.calories), [210, 180, 98])
        XCTAssertTrue(items.allSatisfy(\.confident))
    }

    func testNumberWordsAndDigits() {
        let items = FoodDatabase.shared.parse("I had 3 eggs and a banana")
        XCTAssertEqual(items.map(\.quantity), [3, 1])
    }

    func testUnknownFoodIsFlaggedNotInvented() {
        let item = FoodDatabase.shared.ground("dragon fruit smoothie")
        XCTAssertFalse(item.confident)
        XCTAssertEqual(item.calories, 0)
    }

    func testLongestAliasWins() {
        XCTAssertEqual(FoodDatabase.shared.ground("greek yogurt").name, "greek yogurt")
    }
}

final class PlanBuilderTests: XCTestCase {
    private func input(goal: GoalType, sex: Sex = .male) -> PlanInput {
        PlanInput(sex: sex, age: 28, heightCm: 175, weightKg: 78.5, activity: .light, goal: goal)
    }

    func testLoseGoalEatsLessThanMaintain() {
        let lose = PlanBuilder.build(input(goal: .lose))
        let maintain = PlanBuilder.build(input(goal: .maintain))
        XCTAssertLessThan(lose.calories, maintain.calories)
        XCTAssertLessThan(lose.weeklyChangeKg, 0)
    }

    func testNeverPlansBelowConservativeFloor() {
        var small = input(goal: .lose, sex: .female)
        small.weightKg = 40
        small.heightCm = 150
        XCTAssertGreaterThanOrEqual(PlanBuilder.build(small).calories, 1200)
    }

    func testMacrosAddUpToRoughlyTheCalories() {
        let plan = PlanBuilder.build(input(goal: .build))
        let kcal = plan.proteinG * 4 + plan.carbsG * 4 + plan.fatG * 9
        XCTAssertEqual(Double(kcal), Double(plan.calories), accuracy: 40)
    }

    func testWorkoutDaysAreSpreadOut() {
        XCTAssertEqual(PlanBuilder.workoutWeekdays(daysPerWeek: 3), [2, 4, 6])
    }
}

final class QuietHoursTests: XCTestCase {
    func testOvernightWindow() {
        XCTAssertTrue(Notifier.isQuiet(23 * 60, start: 22 * 60 + 30, end: 6 * 60))
        XCTAssertTrue(Notifier.isQuiet(5 * 60, start: 22 * 60 + 30, end: 6 * 60))
        XCTAssertFalse(Notifier.isQuiet(12 * 60, start: 22 * 60 + 30, end: 6 * 60))
    }
}

@MainActor
final class StoreTests: XCTestCase {
    func testMergeKeepsMealsFromBothDevices() {
        let store = AppStore(fileName: "test-\(UUID().uuidString).json")
        store.addMeals([Meal(name: "Local", calories: 100)])
        var remote = Snapshot()
        remote.meals = [Meal(name: "Watch", calories: 50)]
        remote.updatedAt = Date().addingTimeInterval(60)
        store.merge(remote: remote)
        XCTAssertEqual(Set(store.snapshot.meals.map(\.name)), ["Local", "Watch"])
    }
}

/// The server and the apps must agree on the wire format. The fixture is a real response from /v1/state.
final class WireFormatTests: XCTestCase {
    private func fixture() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "server_state", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testDecodesARealServerSnapshot() throws {
        let snapshot = try JSONDecoder.pulse.decode(Snapshot.self, from: try fixture())
        XCTAssertTrue(snapshot.profile.onboarded)
        XCTAssertEqual(snapshot.profile.name, "Aarav")
        XCTAssertEqual(snapshot.profile.allergies, ["Peanuts"])
        XCTAssertEqual(snapshot.profile.timezone, "Asia/Kolkata")
        XCTAssertEqual(snapshot.meals.first?.calories, 210)
        XCTAssertEqual(snapshot.plan.count, 2)
        XCTAssertNotNil(snapshot.plan[0].exercises[0].sets[0].doneOn)
        XCTAssertNotNil(snapshot.reminders.first?.lastCompleted)
        XCTAssertEqual(snapshot.deletedIds, [])        // the server never sends this key
    }

    func testReEncodedSnapshotKeepsServerKeys() throws {
        let snapshot = try JSONDecoder.pulse.decode(Snapshot.self, from: try fixture())
        let data = try JSONEncoder.pulse.encode(snapshot)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["profile", "meals", "plan", "reminders", "updatedAt", "deletedIds"] {
            XCTAssertNotNil(json[key], key)
        }
        let meal = try XCTUnwrap((json["meals"] as? [[String: Any]])?.first)
        XCTAssertEqual(meal["calories"] as? Int, 210)
        XCTAssertNotNil(meal["date"] as? String)
    }
}

@MainActor
final class TombstoneTests: XCTestCase {
    func testDeletedMealDoesNotComeBackFromAnotherDevice() {
        let store = AppStore(fileName: "test-\(UUID().uuidString).json")
        let meal = Meal(name: "Oops", calories: 400)
        store.addMeals([meal])
        var other = Snapshot()
        other.meals = [meal]
        other.updatedAt = Date().addingTimeInterval(60)
        store.deleteMeal(meal.id)
        store.merge(remote: other)
        XCTAssertTrue(store.snapshot.meals.isEmpty)
        XCTAssertEqual(store.snapshot.deletedIds, [meal.id])
    }

    func testSyncAcknowledgementClearsTombstones() {
        let store = AppStore(fileName: "test-\(UUID().uuidString).json")
        let meal = Meal(name: "Oops", calories: 400)
        store.addMeals([meal])
        store.deleteMeal(meal.id)
        store.acknowledgeSync(of: [meal.id])
        XCTAssertTrue(store.snapshot.deletedIds.isEmpty)
    }
}


/// Stands in for the network so we can check exactly what the app sends when saving an API key.
final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (Int, Data))?
    static var lastRequest: URLRequest?
    static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lastRequest = request
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data(); var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; data.append(buffer, count: n) }
            Self.lastBody = data
        } else { Self.lastBody = request.httpBody }
        let (status, data) = Self.handler?(request) ?? (500, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class ConnectorClientTests: XCTestCase {
    private let client = CloudClient(baseURL: URL(string: "https://pulse.example.com")!, token: "session-token")

    override func setUp() { URLProtocol.registerClass(StubURLProtocol.self) }
    override func tearDown() { URLProtocol.unregisterClass(StubURLProtocol.self); StubURLProtocol.handler = nil }

    func testSavingAKeySendsItOnceOverTheSessionAndOnlyKeepsTheLastFour() async throws {
        StubURLProtocol.handler = { _ in
            (200, Data(#"{"provider":"anthropic","last4":"1234","status":"ok","createdAt":"2026-10-26T10:00:00+00:00","lastUsedAt":null}"#.utf8))
        }
        let info = try await client.saveKey(provider: "anthropic", key: "sk-ant-api03-SECRETSECRETSECRET1234", password: "my password")
        XCTAssertEqual(info.last4, "1234")
        let request = try XCTUnwrap(StubURLProtocol.lastRequest)
        XCTAssertEqual(request.httpMethod, "PUT")
        XCTAssertEqual(request.url?.path, "/v1/connectors/anthropic")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer session-token")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(StubURLProtocol.lastBody)) as? [String: String])
        XCTAssertEqual(body["apiKey"], "sk-ant-api03-SECRETSECRETSECRET1234")
        XCTAssertEqual(body["password"], "my password")
    }

    func testServerErrorsReachTheUserWithoutTheKey() async {
        StubURLProtocol.handler = { _ in (422, Data(#"{"detail":"Claude rejected this key."}"#.utf8)) }
        do {
            _ = try await client.saveKey(provider: "anthropic", key: "sk-ant-api03-SECRETSECRETSECRET1234", password: "pw")
            XCTFail("should have thrown")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Claude rejected this key.")
            XCTAssertFalse(error.localizedDescription.contains("SECRET"))
        }
    }

    func testConnectorListDecodesAndHasNoPlaceToHoldAKey() throws {
        let json = #"{"encryptionAvailable":true,"providers":[{"id":"anthropic","name":"Claude (Anthropic)","hint":"Starts with sk-ant-"}],"connectors":[{"provider":"anthropic","last4":"1234","status":"ok","createdAt":"x","lastUsedAt":null}]}"#
        let list = try JSONDecoder().decode(ConnectorList.self, from: Data(json.utf8))
        XCTAssertTrue(list.encryptionAvailable)
        XCTAssertEqual(list.connectors.first?.last4, "1234")
        // ConnectorInfo has only provider, last4, status and dates, so a key can never be stored in it.
        XCTAssertEqual(Mirror(reflecting: list.connectors[0]).children.compactMap(\.label).sorted(),
                       ["createdAt", "last4", "lastUsedAt", "provider", "status"])
    }

    func testRemovingAKeySendsThePassword() async throws {
        StubURLProtocol.handler = { _ in (204, Data()) }
        try await client.removeKey(provider: "openai", password: "pw")
        XCTAssertEqual(StubURLProtocol.lastRequest?.url?.path, "/v1/connectors/openai/remove")
        XCTAssertEqual(StubURLProtocol.lastRequest?.httpMethod, "POST")
    }
}
