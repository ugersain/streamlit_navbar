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
