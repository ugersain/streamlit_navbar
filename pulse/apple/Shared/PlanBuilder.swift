import Foundation

enum Sex: String, CaseIterable, Codable { case male, female, unspecified }
enum ActivityLevel: String, CaseIterable, Codable {
    case sitting, light, active, veryActive

    var factor: Double {
        switch self {
        case .sitting: return 1.2
        case .light: return 1.375
        case .active: return 1.55
        case .veryActive: return 1.725
        }
    }
}
enum GoalType: String, CaseIterable, Codable { case lose, build, maintain, healthier }

struct PlanInput {
    var sex: Sex
    var age: Int
    var heightCm: Double
    var weightKg: Double
    var activity: ActivityLevel
    var goal: GoalType
}

struct PlanResult: Equatable {
    var calories: Int
    var proteinG: Int
    var carbsG: Int
    var fatG: Int
    /// Estimated weekly change in kg (negative = loss).
    var weeklyChangeKg: Double
}

/// Mifflin-St Jeor estimate. General guidance only, never medical advice.
enum PlanBuilder {
    static func build(_ input: PlanInput) -> PlanResult {
        let sexTerm: Double
        switch input.sex {
        case .male: sexTerm = 5
        case .female: sexTerm = -161
        case .unspecified: sexTerm = -78
        }
        let bmr = 10 * input.weightKg + 6.25 * input.heightCm - 5 * Double(input.age) + sexTerm
        let tdee = bmr * input.activity.factor

        let adjustment: Double
        switch input.goal {
        case .lose: adjustment = -500
        case .build: adjustment = 300
        case .maintain, .healthier: adjustment = 0
        }
        // Never plan below a conservative floor.
        let floor = max(1200, bmr * 0.9)
        let calories = max(tdee + adjustment, floor)
        let realAdjustment = calories - tdee

        let proteinPerKg = (input.goal == .lose || input.goal == .build) ? 1.8 : 1.4
        let protein = (input.weightKg * proteinPerKg).rounded()
        let fat = (calories * 0.25 / 9).rounded()
        let carbs = max(0, ((calories - protein * 4 - fat * 9) / 4).rounded())

        return PlanResult(
            calories: Int((calories / 10).rounded() * 10),
            proteinG: Int(protein), carbsG: Int(carbs), fatG: Int(fat),
            weeklyChangeKg: (realAdjustment * 7 / 7700 * 10).rounded() / 10
        )
    }

    /// Spread workouts across the week, avoiding back-to-back days where possible.
    static func workoutWeekdays(daysPerWeek: Int) -> [Int] {
        switch min(max(daysPerWeek, 1), 6) {
        case 1: return [4]
        case 2: return [2, 5]
        case 3: return [2, 4, 6]
        case 4: return [2, 4, 6, 7]
        case 5: return [2, 3, 5, 6, 7]
        default: return [2, 3, 4, 6, 7, 1]
        }
    }
}
