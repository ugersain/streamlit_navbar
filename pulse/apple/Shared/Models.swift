import Foundation

struct Meal: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var quantity: Double = 1
    var unit: String = "serving"
    var calories: Int
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var date = Date()
    var source: Source = .manual

    enum Source: String, Codable { case manual, voice }
}

struct ExerciseSet: Codable, Identifiable, Hashable {
    var id = UUID()
    var weightKg: Double
    var reps: Int
    var doneOn: Date?

    var isDoneToday: Bool { doneOn.map(Calendar.current.isDateInToday) ?? false }
}

struct Exercise: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var restSeconds: Int = 90
    var sets: [ExerciseSet]
}

struct WorkoutDay: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Calendar weekday: 1 = Sunday ... 7 = Saturday.
    var weekday: Int
    var title: String
    var startMinutes: Int
    var exercises: [Exercise]
}

struct Reminder: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    /// Minutes after midnight, local time.
    var minutes: Int
    var lastCompleted: Date?
    var snoozedUntil: Date?
    /// One-off reminders (for example from the assistant) are removed once completed.
    var oneOff = false

    var isDoneToday: Bool { lastCompleted.map(Calendar.current.isDateInToday) ?? false }
}

struct Profile: Codable, Hashable {
    var name = ""
    var calorieGoal = 2000
    var proteinGoal = 120
    var carbsGoal = 220
    var fatGoal = 60
    var activeGoal = 600
    var diet = "Vegetarian"
    var quietStart = 22 * 60 + 30
    var quietEnd = 6 * 60
    var onboarded = false
}

struct Snapshot: Codable {
    var profile = Profile()
    var meals: [Meal] = []
    var plan: [WorkoutDay] = []
    var reminders: [Reminder] = []
    var updatedAt = Date.distantPast
}

extension JSONEncoder {
    static let pulse: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

extension JSONDecoder {
    static let pulse: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension Int {
    /// 390 -> "6:30 AM"
    var clockString: String {
        let hour24 = (self / 60) % 24
        let minute = self % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return String(format: "%d:%02d %@", hour12, minute, hour24 < 12 ? "AM" : "PM")
    }
}

extension WorkoutDay {
    static func sample() -> [WorkoutDay] {
        func ex(_ name: String, _ kg: Double, _ reps: Int, sets: Int = 3, rest: Int = 90) -> Exercise {
            Exercise(name: name, restSeconds: rest, sets: (0..<sets).map { _ in ExerciseSet(weightKg: kg, reps: reps) })
        }
        let upper = [
            ex("Bench press", 40, 8, sets: 4),
            ex("Overhead press", 25, 10),
            ex("Incline dumbbell press", 14, 10),
            ex("Seated cable row", 45, 12),
            ex("Triceps pushdown", 20, 12),
        ]
        let lower = [
            ex("Back squat", 50, 8, sets: 4),
            ex("Romanian deadlift", 50, 10),
            ex("Leg press", 100, 12),
            ex("Calf raise", 40, 15),
        ]
        // Mon, Wed, Fri, Sat
        return [
            WorkoutDay(weekday: 2, title: "Upper body", startMinutes: 18 * 60 + 30, exercises: upper),
            WorkoutDay(weekday: 4, title: "Lower body", startMinutes: 18 * 60 + 30, exercises: lower),
            WorkoutDay(weekday: 6, title: "Upper body", startMinutes: 18 * 60 + 30, exercises: upper),
            WorkoutDay(weekday: 7, title: "Lower body", startMinutes: 18 * 60 + 30, exercises: lower),
        ]
    }
}

extension Reminder {
    static func defaults() -> [Reminder] {
        [
            Reminder(title: "Brush teeth and stretch", minutes: 6 * 60 + 35),
            Reminder(title: "Breakfast", minutes: 7 * 60 + 15),
            Reminder(title: "Drink water", minutes: 10 * 60 + 30),
            Reminder(title: "Lunch", minutes: 13 * 60),
            Reminder(title: "Drink water", minutes: 15 * 60 + 30),
            Reminder(title: "Wind down", minutes: 22 * 60),
        ]
    }
}
